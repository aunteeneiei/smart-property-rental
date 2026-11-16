# SmartLiving Property - Smart Property Rental & Deposit Management (CSI301)

ระบบจัดการสัญญาเช่าอสังหาริมทรัพย์และเงินประกันบน Ethereum Blockchain (Sepolia Testnet)  
พัฒนาตามโจทย์ที่ 4 รายวิชา CSI301 มหาวิทยาลัยศรีปทุม

---

## 📌 ข้อมูลการส่งงาน (Project Submission)

* **Contract Address:** `0x6990636d74eaba15c5d59db64a63de707b0399c2`
* **Etherscan Verified URL:** [https://sepolia.etherscan.io/address/0x6990636d74eaba15c5d59db64a63de707b0399c2#code](https://sepolia.etherscan.io/address/0x6990636d74eaba15c5d59db64a63de707b0399c2#code)
* **GitHub Repository:** [https://github.com/aunteeneiei/smart-property-rental](https://github.com/aunteeneiei/smart-property-rental)
* **Live GitHub Page:** [https://aunteeneiei.github.io/smart-property-rental/](https://aunteeneiei.github.io/smart-property-rental/)

---

## 🚀 ฟังก์ชันหลักของระบบ (7 Functional Requirements)

1. **ลงทะเบียนทรัพย์สิน (`registerProperty`):** เจ้าของห้องสร้างรายการห้องเช่า กำหนดค่าเช่า และเงินประกัน
2. **สร้างสัญญาเช่า (`createRentalAgreement`):** ระบุคู่สัญญา (ผู้เช่า), วันเริ่มต้น, วันสิ้นสุด และเงื่อนไขสำคัญ
3. **ยืนยันสัญญา (`confirmAgreement`):** ทั้งผู้เช่าและเจ้าของห้องต้องกดยืนยันผ่าน Wallet เพื่อให้สัญญาพร้อมทำงาน
4. **ฝากเงินประกัน (`depositSecurity`):** ผู้เช่าโอนเงินประกัน (ETH) เข้าสู่ Smart Contract (Escrow)
5. **บันทึกค่าเช่า (`recordRentalPayment`):** ผู้เช่าชำระค่าเช่ารายงวด โดยเงินจะโอนให้เจ้าของทันทีและบันทึกประวัติงวด
6. **คืนเงินประกัน (`refundDeposit`):** เมื่อสิ้นสุดสัญญา เจ้าของตรวจสภาพห้อง และระบบคืนเงินประกันตามที่ได้รับอนุมัติ
7. **จัดการข้อโต้แย้ง (`raiseDispute` & `resolveDispute`):** กรณีมีข้อพิพาท ผู้มีอำนาจ (SmartLiving Arbitrator) จะพิจารณาและตัดสินก่อนปล่อยเงิน

---

## 🛡️ กฎทางธุรกิจและความปลอดภัย (Security & Business Rules)
* การหักเงินประกันต้องระบุเหตุผลเสมอ
* ต้องไม่สามารถคืนเงินเกินยอดคงเหลือของเงินประกัน
* ป้องกัน Reentrancy Attack ด้วย Checks-Effects-Interactions (CEI) และ ReentrancyGuard
