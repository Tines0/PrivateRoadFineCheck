# Roadside Privacy Check (Zama FHEVM)

A minimal dApp demonstrating **private roadside fine verification** on Zama’s FHE EVM (FHEVM). Police officers compare a car’s **encrypted measured speed** against an **encrypted road speed limit**. Only the **verdict** (fine / no fine) is revealed to the officer; raw values remain private at all times.

---

## ✨ Features

* **Encrypted data in / encrypted data out**: limits and measured speeds are sent as ciphertexts; the contract outputs an encrypted boolean (fine / no fine).
* **Public vs. private decryption paths**: admin-side limits can be made publicly decryptable for audits; roadside verdicts are **user-decrypt only**.
* **Officer UX**: hash license plate locally with a salt, submit private check, and decrypt the verdict via EIP‑712 based user decryption.
* **Admin tools**: set encrypted speed limits per road; optional plain setter for local testing.
* **Relayer SDK 0.2.0 API**: uses `createEncryptedInput()` positional parameters and `createEIP712()` for `userDecrypt`.

---

## 📁 Project layout

```
frontend/
└─ public/
   └─ index.html        # the single-page dApp (no build step required)
contracts/              # (optional) Solidity sources
hardhat.config.ts       # (optional) if you keep the contract here
```

> Your HTML lives at **`frontend/public/index.html`**. You can serve it as a static site (any CDN/GitHub Pages/Netlify) or locally with a tiny HTTP server.

---

## 🚀 Quick start (frontend only)

### 1) Prerequisites

* Node.js ≥ 18 (for local static server)
* A browser wallet (MetaMask) connected to **Sepolia**

### 2) Serve the static page

From the repo root:

```bash
# Option A: using npx http-server (no install)
npx http-server frontend/public -p 5173 -c-1

# Option B: using serve
npx serve frontend/public -l 5173
```

Open **[http://localhost:5173](http://localhost:5173)** in your browser.

### 3) Configure (optional)

`index.html` contains a small `CONFIG` block with:

```js
window.CONFIG = {
  NETWORK_NAME: "Sepolia",
  CHAIN_ID_HEX: "0xaa36a7",
  CONTRACT_ADDRESS: "0x31964284b93757861F90Dd0434008b53eFf74A39",
  RELAYER_URL: "https://relayer.testnet.zama.cloud"
};
```

Adjust if you redeploy or use a different relayer endpoint.

---

## 🔐 How it works (high level)

1. **Admin sets the limit**: the Relayer SDK encrypts `limit (km/h)` → contract stores encrypted `euint` and marks it for later decryption/reading (ACL).
2. **Officer checks a vehicle**:

   * Officer inputs `roadId`, plaintext `speed`, and a **license plate hash** (plate + salt, hashed locally on the client).
   * Client uses Relayer SDK 0.2.0 to encrypt the speed and submits `(roadId, plateHash, speedHandle, proof)` to the contract.
   * The contract compares `speedCt` vs `limitCt` homomorphically and emits an **encrypted verdict handle**.
3. **Verdict decryption**: the officer calls `userDecrypt` via Relayer with an **EIP‑712 signature** and obtains a boolean `fine / no fine`.

No party learns the raw speed or limit values from on-chain data.

---

## 🧩 Main user flows

### Officer

* Enter `Road ID`, `License Plate`, and `Salt`.
* Set measured speed (km/h).
* **Submit Private Check** → waits for tx → decrypts the verdict via Relayer `userDecrypt`.

### Admin

* Enter `Road ID` and the **limit (km/h)**.
* Click **Set Encrypted Limit** (production) or **Set Plain Limit (dev)** (development only).

> The UI includes rich console logs (`[APP]`, `[FHE]`, `[DBG]`) to audit each step without exposing secrets visually.

---

## 🛠 Development & Deployment

### Install tooling (optional)

If you also keep/modify the contract in this repo:

```bash
npm i
npm i -D hardhat hardhat-deploy @nomicfoundation/hardhat-toolbox
```

### Compile / deploy (optional)

```bash
npx hardhat compile
npx hardhat deploy --network sepolia
```

Update the deployed address in `frontend/public/index.html` → `CONFIG.CONTRACT_ADDRESS`.

### Host the frontend

* **Static hosting**: push `frontend/public` to any static host (GitHub Pages, Netlify, Vercel, S3, Cloudflare Pages).
* **Local**: run one of the static servers shown above.


