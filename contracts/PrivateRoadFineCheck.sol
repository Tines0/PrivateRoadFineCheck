// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/* Zama FHE */
import { FHE, ebool, euint16, externalEuint16 } from "@fhevm/solidity/lib/FHE.sol";
/* Network config (Sepolia) */
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

/**
 * @title PrivateRoadFineCheck
 * @notice Roadside private fine check:
 *         - Owner uploads per-road speed limit (encrypted or plain).
 *         - Officer submits encrypted measured speed; contract returns private verdict (ebool).
 *         - Only the officer (msg.sender) can decrypt the verdict (user-decrypt).
 *
 * Verdict semantics: 1 = FINE (speed > limit), 0 = OK.
 */
contract PrivateRoadFineCheck is SepoliaConfig {
    /* ───── Ownable ───── */
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }

    constructor() { owner = msg.sender; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    /* ───── Storage ───── */

    struct RoadCfg {
        bool exists;          // есть ли лимит для дороги
        bool isPlain;         // true => используем plainLimit, иначе encLimit
        uint16 plainLimit;    // лимит в км/ч в открытом виде (dev)
        euint16 encLimit;     // лимит в зашифрованном виде
    }

    mapping(uint256 => RoadCfg) private _road;

    /* ───── Events ───── */

    /// @dev Эмитим офицеру handle вердикта, чтобы он мог userDecrypt
    event VehicleChecked(
        address indexed officer,
        uint256 indexed roadId,
        bytes32 plateHash,
        bytes32 verdictHandle // ebool
    );

    event RoadLimitSet(uint256 indexed roadId, bool encrypted, uint16 plainValueIfAny);
    event RoadLimitCleared(uint256 indexed roadId);

    /* ───── View helpers ───── */

    function version() external pure returns (string memory) {
        return "PrivateRoadFineCheck/1.0.0-sepolia";
    }

    function hasLimit(uint256 roadId) external view returns (bool) {
        return _road[roadId].exists;
    }

    function getPlain(uint256 roadId) external view returns (bool exists, bool isPlain, uint16 plain) {
        RoadCfg storage r = _road[roadId];
        return (r.exists, r.isPlain, r.plainLimit);
    }

    /// Возвращаем bytes32-хэндл зашифрованного лимита (если есть), для отладки/проверок
    function getEncryptedHandle(uint256 roadId) external view returns (bytes32) {
        RoadCfg storage r = _road[roadId];
        if (!r.exists || r.isPlain) return bytes32(0);
        return FHE.toBytes32(r.encLimit);
    }

    /* ───── Admin: set limits ───── */

    /// @notice Установить ЗАШИФРОВАННЫЙ лимит (km/h)
    /// @param roadId   идентификатор дороги
    /// @param limitExt bytes32-хэндл externalEuint16 (SDK)
    /// @param proof    доказательство целостности
    function setLimit(
        uint256 roadId,
        externalEuint16 limitExt,
        bytes calldata proof
    ) external onlyOwner
    {
        require(roadId != 0, "Bad roadId");
        euint16 lim = FHE.fromExternal(limitExt, proof);

        // важно: разрешение контракту продолжать использовать это значение
        FHE.allowThis(lim);

        RoadCfg storage r = _road[roadId];
        r.exists = true;
        r.isPlain = false;
        r.encLimit = lim;
        // plainLimit игнорируется

        emit RoadLimitSet(roadId, true, 0);
    }

    /// @notice Установить ПЛЕЙН лимит (только для дев/простых демо)
    function setLimitPlain(uint256 roadId, uint16 limitKmH) external onlyOwner {
        require(roadId != 0, "Bad roadId");
        require(limitKmH > 0, "Bad limit");

        RoadCfg storage r = _road[roadId];
        r.exists = true;
        r.isPlain = true;
        r.plainLimit = limitKmH;
        // encLimit остаётся лежать, но мы его не используем

        emit RoadLimitSet(roadId, false, limitKmH);
    }

    /// @notice Очистить лимит для дороги.
    /// Важно: НЕЛЬЗЯ делать `delete` по euint16 — это не поддерживается в языке.
    /// Просто помечаем отсутствующим и, если надо, зануляем plain.
    function clearLimit(uint256 roadId) external onlyOwner {
        RoadCfg storage r = _road[roadId];
        require(r.exists, "No limit");
        r.exists = false;
        r.isPlain = false;
        r.plainLimit = 0;
        // r.encLimit оставляем как есть (не используется)
        emit RoadLimitCleared(roadId);
    }

    /* ───── Roadside check ───── */

    /**
     * @notice Офицер присылает: дорога, plateHash (на устройстве), скорость (encrypted).
     *         Контракт сравнивает и возвращает ebool-вердикт: 1 = FINE (превышение), 0 = OK.
     *         Право на расшифровку даётся офицеру (msg.sender).
     *
     * @param roadId     идентификатор дороги
     * @param plateHash  keccak256(plate | '|' | salt) — не используется в логике, но пишем в событие
     * @param speedExt   externalEuint16 (как bytes32 в ABI)
     * @param proof      доказательство целостности от Relayer SDK
     * @return verdictCt шифротекст вердикта (ебул)
     */
    function checkVehicle(
        uint256 roadId,
        bytes32 plateHash,
        externalEuint16 speedExt,
        bytes calldata proof
    ) external returns (ebool verdictCt)
    {
        RoadCfg storage r = _road[roadId];
        require(r.exists, "Limit not set");

        // Декод входа (если handle/proof невалиден — будет revert внутри fromExternal)
        euint16 speed = FHE.fromExternal(speedExt, proof);

        // Получаем лимит: либо plain → asEuint16, либо enc
        euint16 limitCt = r.isPlain ? FHE.asEuint16(r.plainLimit) : r.encLimit;

        // Сравнение: превышение?
        ebool fine = FHE.gt(speed, limitCt); // true => штраф

        // ACL: офицеру право на user-decrypt результата
        FHE.allow(fine, msg.sender);

        // (опционально) контракту — если дальше будем читать:
        FHE.allowThis(fine);

        emit VehicleChecked(msg.sender, roadId, plateHash, FHE.toBytes32(fine));
        return fine;
    }

    /* ───── Debug helper ───── */

    /// @notice Чистая проверка корректности handle/proof без записи в стор.
    function selfTestProof(
        externalEuint16 valueExt,
        bytes calldata proof
    ) external returns (bytes32 handle)
    {
        euint16 v = FHE.fromExternal(valueExt, proof);
        FHE.allowThis(v);
        handle = FHE.toBytes32(v);
    }
}
