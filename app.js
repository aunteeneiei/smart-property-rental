// SmartLiving Property Management DApp Controller
const CONTRACT_ADDRESS = "0x6990636d74eaba15c5d59db64a63de707b0399c2";
let CONTRACT_ABI = null;

let provider;
let signer;
let contract;
let userAddress;

window.addEventListener('DOMContentLoaded', async () => {
    document.getElementById('contractAddrDisplay').innerText = CONTRACT_ADDRESS;
    document.getElementById('btnConnectWallet').addEventListener('click', connectWallet);

    try {
        const res = await fetch('abi.json');
        CONTRACT_ABI = await res.json();
        console.log('ABI loaded successfully');
    } catch (err) {
        console.error('Failed to load ABI:', err);
    }

    setupEventListeners();
});

async function connectWallet() {
    if (!window.ethereum) {
        alert('กรุณาติดตั้ง MetaMask เพื่อใช้งาน');
        return;
    }

    try {
        provider = new ethers.BrowserProvider(window.ethereum);
        await provider.send("eth_requestAccounts", []);
        signer = await provider.getSigner();
        userAddress = await signer.getAddress();

        const network = await provider.getNetwork();
        document.getElementById('networkName').innerText = network.name === 'unknown' ? `Chain ID: ${network.chainId}` : network.name;
        document.getElementById('userAccount').innerText = `${userAddress.substring(0, 6)}...${userAddress.substring(38)}`;
        document.getElementById('btnConnectWallet').classList.add('hidden');
        document.getElementById('connectedBox').classList.remove('hidden');

        const balance = await provider.getBalance(userAddress);
        document.getElementById('userBalance').innerText = `${parseFloat(ethers.formatEther(balance)).toFixed(4)} ETH`;

        if (CONTRACT_ABI) {
            contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);
            refreshStats();
        }

        window.ethereum.on('accountsChanged', () => window.location.reload());
        window.ethereum.on('chainChanged', () => window.location.reload());
    } catch (err) {
        console.error(err);
        alert(err.message || 'เชื่อมต่อ Wallet ล้มเหลว');
    }
}

async function refreshStats() {
    if (!contract) return;
    try {
        const bal = await contract.getContractBalance();
        const pCount = await contract.propertyCount();
        const aCount = await contract.agreementCount();
        const arb = await contract.arbitrator();

        document.getElementById('statBalance').innerText = `${ethers.formatEther(bal)} ETH`;
        document.getElementById('statProperties').innerText = pCount.toString();
        document.getElementById('statAgreements').innerText = aCount.toString();
        document.getElementById('statArbitrator').innerText = `${arb.substring(0, 6)}...${arb.substring(38)}`;
    } catch (e) {
        console.warn('Stat refresh warning:', e);
    }
}

function setupEventListeners() {
    // 1. Register Property
    document.getElementById('btnRegister').addEventListener('click', async () => {
        if (!checkReady()) return;
        const info = document.getElementById('regRoomInfo').value.trim();
        const rent = document.getElementById('regRentEth').value.trim();
        const dep = document.getElementById('regDepositEth').value.trim();

        if (!info || !rent || !dep) return alert('กรุณากรอกข้อมูลห้องให้ครบถ้วน');

        try {
            const rentWei = ethers.parseEther(rent);
            const depWei = ethers.parseEther(dep);
            const tx = await contract.registerProperty(info, rentWei, depWei);
            alert('ส่งธุรกรรมแล้ว รอการยืนยันบน Blockchain...');
            await tx.wait();
            alert('ลงทะเบียนห้องพักสำเร็จ!');
            refreshStats();
        } catch (e) { handleError(e); }
    });

    // 2. Create Agreement
    document.getElementById('btnCreateAg').addEventListener('click', async () => {
        if (!checkReady()) return;
        const propId = document.getElementById('agPropId').value.trim();
        const tenant = document.getElementById('agTenant').value.trim();
        const startDays = parseInt(document.getElementById('agStartDays')?.value || '0');
        const months = parseInt(document.getElementById('agDurationMonths')?.value || '12');
        const terms = document.getElementById('agTerms').value.trim();

        if (!propId || !ethers.isAddress(tenant) || !terms) return alert('กรุณากรอกข้อมูลและที่อยู่ผู้เช่าให้ถูกต้อง');

        try {
            const now = Math.floor(Date.now() / 1000);
            const startTime = now + (startDays * 86400);
            const endTime = startTime + (months * 30 * 86400);
            const tx = await contract.createRentalAgreement(propId, tenant, startTime, endTime, terms);
            alert('ส่งธุรกรรมสร้างสัญญาแล้ว...');
            await tx.wait();
            alert('สร้างสัญญาเช่าสำเร็จ!');
            refreshStats();
        } catch (e) { handleError(e); }
    });

    // 3. Confirm Agreement
    document.getElementById('btnConfirmAg').addEventListener('click', async () => {
        if (!checkReady()) return;
        const agId = document.getElementById('confAgId').value.trim();
        if (!agId) return alert('กรุณาใส่ Agreement ID');
        try {
            const tx = await contract.confirmAgreement(agId);
            alert('กำลังยืนยันสัญญา...');
            await tx.wait();
            alert('ยืนยันสัญญาสำเร็จ!');
        } catch (e) { handleError(e); }
    });

    // 4. Deposit Security
    document.getElementById('btnDeposit').addEventListener('click', async () => {
        if (!checkReady()) return;
        const agId = document.getElementById('depAgId').value.trim();
        const eth = document.getElementById('depEthAmount').value.trim();
        if (!agId || !eth) return alert('กรุณาใส่ Agreement ID และยอดเงินประกัน (ETH)');
        try {
            const value = ethers.parseEther(eth);
            const tx = await contract.depositSecurity(agId, { value });
            alert('กำลังโอนเงินประกันเข้าสู่ Smart Contract...');
            await tx.wait();
            alert('วางเงินประกันสำเร็จ สัญญาเริ่มต้นทำงาน (Active)!');
            refreshStats();
        } catch (e) { handleError(e); }
    });

    // 5. Pay Rent
    document.getElementById('btnPayRent').addEventListener('click', async () => {
        if (!checkReady()) return;
        const agId = document.getElementById('rentAgId').value.trim();
        const eth = document.getElementById('rentEthAmount').value.trim();
        if (!agId || !eth) return alert('กรุณาใส่ Agreement ID และยอดค่าเช่า (ETH)');
        try {
            const value = ethers.parseEther(eth);
            const tx = await contract.recordRentalPayment(agId, { value });
            alert('กำลังชำระค่าเช่า...');
            await tx.wait();
            alert('ชำระค่าเช่าและบันทึกประวัติงวดสำเร็จ!');
            refreshStats();
        } catch (e) { handleError(e); }
    });

    // 5.1 Query History
    document.getElementById('btnQueryHistory').addEventListener('click', async () => {
        if (!checkReady()) return;
        const agId = document.getElementById('histAgId').value.trim();
        if (!agId) return alert('กรุณาใส่ Agreement ID');
        try {
            const list = await contract.getRentalPaymentHistory(agId);
            const box = document.getElementById('historyBox');
            box.innerHTML = '';
            if (list.length === 0) {
                box.innerHTML = '<p class="text-gray-400 text-sm">ยังไม่มีประวัติการชำระเงินสำหรับสัญญานี้</p>';
                return;
            }
            list.forEach(item => {
                const d = new Date(Number(item.paidTimestamp) * 1000).toLocaleString('th-TH');
                box.innerHTML += `<div class="p-2 bg-slate-800 rounded border border-slate-700 text-xs mb-1 flex justify-between items-center"><span><b>งวดที่ ${item.periodIndex}</b> | ${ethers.formatEther(item.amount)} ETH</span><span class="text-gray-400">${d}</span></div>`;
            });
        } catch (e) { handleError(e); }
    });

    // 6. Inspection & Refund
    document.getElementById('btnInspect').addEventListener('click', async () => {
        if (!checkReady()) return;
        const agId = document.getElementById('inspAgId').value.trim();
        const eth = document.getElementById('inspDeductEth').value.trim() || '0';
        const reason = document.getElementById('inspReason').value.trim();
        if (!agId) return alert('กรุณาใส่ Agreement ID');
        try {
            const deductWei = ethers.parseEther(eth);
            const tx = await contract.recordRoomInspection(agId, deductWei, reason);
            alert('กำลังบันทึกผลตรวจสภาพห้อง...');
            await tx.wait();
            alert('บันทึกผลตรวจสภาพห้องสำเร็จ!');
        } catch (e) { handleError(e); }
    });

    document.getElementById('btnAgree').addEventListener('click', async () => {
        if (!checkReady()) return;
        const agId = (document.getElementById('agreeAgId') || document.getElementById('inspAgId'))?.value?.trim();
        if (!agId) return alert('กรุณาใส่ Agreement ID');

        try {
            const tx = await contract.agreeToInspectionDeduction(agId);
            alert('กำลังส่งการยินยอม...');
            await tx.wait();
            alert('ผู้เช่ายินยอมรับการหักเงินประกันเรียบร้อย');
        } catch (e) { handleError(e); }
    });

    document.getElementById('btnRefund').addEventListener('click', async () => {
        if (!checkReady()) return;
        const agId = (document.getElementById('refAgId') || document.getElementById('inspAgId'))?.value?.trim();
        if (!agId) return alert('กรุณาใส่ Agreement ID');
        try {
            const tx = await contract.refundDeposit(agId);
            alert('กำลังดำเนินการคืนเงินประกัน...');
            await tx.wait();
            alert('คืนเงินประกันตามที่อนุมัติสำเร็จ!');
            refreshStats();
        } catch (e) { handleError(e); }
    });

    // 7. Dispute
    document.getElementById('btnRaiseDisp').addEventListener('click', async () => {
        if (!checkReady()) return;
        const agId = document.getElementById('dispAgId').value.trim();
        const reason = document.getElementById('dispReason').value.trim();
        if (!agId || !reason) return alert('กรุณาใส่ ID และเหตุผล');
        try {
            const tx = await contract.raiseDispute(agId, reason);
            await tx.wait();
            alert('เปิดข้อพิพาทเรียบร้อย!');
        } catch (e) { handleError(e); }
    });

    document.getElementById('btnResolveDisp').addEventListener('click', async () => {
        if (!checkReady()) return;
        const agId = document.getElementById('resAgId').value.trim();
        const pLandlord = document.getElementById('resLandlordEth').value.trim() || '0';
        const rTenant = document.getElementById('resTenantEth').value.trim() || '0';
        const notes = document.getElementById('resNotes').value.trim();
        if (!agId || !notes) return alert('กรุณากรอกข้อมูลให้ครบถ้วน');
        try {
            const payWei = ethers.parseEther(pLandlord);
            const refWei = ethers.parseEther(rTenant);
            const tx = await contract.resolveDispute(agId, payWei, refWei, notes);
            alert('ผู้มีอำนาจกำลังตัดสินข้อพิพาท...');
            await tx.wait();
            alert('ตัดสินข้อพิพาทและปล่อยเงินเรียบร้อย!');
            refreshStats();
        } catch (e) { handleError(e); }
    });
}

function checkReady() {
    if (!contract) {
        alert('กรุณาเชื่อมต่อ MetaMask ก่อนทำรายการ');
        return false;
    }
    return true;
}

function handleError(err) {
    console.error(err);
    alert(err.reason || err.shortMessage || err.message || 'ธุรกรรมล้มเหลว');
}
