// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title PropertyRentalManagement
 * @dev ระบบจัดการสัญญาเช่าอสังหาริมทรัพย์และเงินประกัน (Smart Property Rental & Deposit Management)
 *      สำหรับ บริษัท SmartLiving Property
 * 
 * ฟังก์ชันหลักครบถ้วนตามข้อกำหนด 7 ประการ:
 * 1. registerProperty()        - เจ้าของห้องลงทะเบียนห้องเช่า ค่าเช่า และเงินประกัน
 * 2. createRentalAgreement()   - สร้างสัญญาเช่า ระบุคู่สัญญา วันเริ่ม วันสิ้นสุด เงื่อนไข
 * 3. confirmAgreement()         - ผู้เช่าและเจ้าของห้องยืนยันการยอมรับเงื่อนไขด้วย Wallet ของตน
 * 4. depositSecurity()          - ผู้เช่าโอนเงินประกันในรูปแบบ ETH เข้าสู่ Smart Contract
 * 5. recordRentalPayment()      - ผู้เช่าชำระค่าเช่า และบันทึกประวัติการชำระเงินแต่ละงวด
 * 6. refundDeposit()            - คืนเงินประกันเมื่อสิ้นสุดสัญญาและผ่านการตรวจสภาพห้องตามยอดที่อนุมัติ
 * 7. raiseDispute() / resolveDispute() - จัดการข้อโต้แย้งโดยผู้มีอำนาจ (Arbitrator/Admin) พิจารณาและบันทึกผลก่อนปล่อยเงิน
 *
 * กฎทางธุรกิจสำคัญ:
 * - การหักเงินประกันต้องมีเหตุผลและไม่สามารถคืนเงินเกินยอดเงินประกันคงเหลือ
 * - ออกแบบตามหลัก Checks-Effects-Interactions (CEI) และมี Reentrancy Protection
 */
contract PropertyRentalManagement {

    // --- ENUMS ---
    enum PropertyStatus { Available, Rented, Inactive }
    enum AgreementStatus { Created, Confirmed, Active, Inspected, Disputed, Completed, Cancelled }

    // --- STRUCTS ---
    struct Property {
        uint256 propertyId;
        address payable landlord;
        string roomInfo;             // ข้อมูลห้องพัก / เลขที่ห้อง
        uint256 rentPrice;           // ค่าเช่าต่องวด (หน่วย Wei)
        uint256 depositRequired;     // เงินประกันที่ต้องวาง (หน่วย Wei)
        PropertyStatus status;
        bool exists;
    }

    struct RentalAgreement {
        uint256 agreementId;
        uint256 propertyId;
        address payable landlord;
        address payable tenant;
        uint256 rentPrice;           // ค่าเช่าต่องวด
        uint256 depositRequired;     // ยอดเงินประกันที่ตกลง
        uint256 depositBalance;      // ยอดเงินประกันที่เก็บอยู่ใน Contract ปัจจุบัน
        uint256 startTime;           // วันเริ่มต้นสัญญา (Unix Timestamp)
        uint256 endTime;             // วันสิ้นสุดสัญญา (Unix Timestamp)
        string terms;                // เงื่อนไขและข้อตกลงสำคัญ
        bool landlordConfirmed;      // เจ้าของห้องยืนยันแล้วหรือไม่
        bool tenantConfirmed;        // ผู้เช่ายืนยันแล้วหรือไม่
        AgreementStatus status;
        bool exists;
    }

    struct RentalPaymentRecord {
        uint256 paymentId;
        uint256 agreementId;
        uint256 periodIndex;         // งวดที่ชำระ (เช่น งวดที่ 1, 2, 3...)
        uint256 amount;              // จำนวนเงินค่าเช่า (Wei)
        uint256 paidTimestamp;       // เวลาที่ชำระ
        address paidBy;
    }

    struct InspectionResult {
        bool isInspected;
        uint256 deductionAmount;     // จำนวนเงินประกันที่ขอหักเป็นค่าเสียหาย
        string deductionReason;      // เหตุผลการหักเงินประกัน
        bool tenantAgreed;           // ผู้เช่ายินยอมรับการหักเงินหรือไม่
    }

    struct DisputeRecord {
        bool isDisputed;
        address raisedBy;
        string disputeReason;        // เหตุผลข้อโต้แย้ง
        uint256 raisedTimestamp;
        bool isResolved;
        uint256 payoutToLandlord;    // ยอดเงินที่ตัดสินจ่ายให้เจ้าของห้อง
        uint256 refundToTenant;      // ยอดเงินที่ตัดสินคืนให้ผู้เช่า
        string resolutionNotes;      // บันทึกผลการพิจารณาของผู้มีอำนาจ
    }

    // --- STATE VARIABLES ---
    address public arbitrator;       // ผู้มีอำนาจชี้ขาดข้อพิพาท (SmartLiving Property Admin)
    uint256 public propertyCount;
    uint256 public agreementCount;
    uint256 public paymentCount;

    mapping(uint256 => Property) public properties;
    mapping(uint256 => RentalAgreement) internal _agreements;
    mapping(uint256 => InspectionResult) public inspectionResults;
    mapping(uint256 => DisputeRecord) public disputeRecords;
    mapping(uint256 => RentalPaymentRecord[]) public agreementPaymentHistory;

    // ระบบ Reentrancy Guard
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "ReentrancyGuard: reentrant call");
        _locked = 2;
        _;
        _locked = 1;
    }

    // --- MODIFIERS ---
    modifier onlyArbitrator() {
        require(msg.sender == arbitrator, "Only SmartLiving arbitrator can perform this action");
        _;
    }

    modifier onlyLandlord(uint256 _propertyId) {
        require(properties[_propertyId].landlord == msg.sender, "Only property landlord can perform this action");
        _;
    }

    modifier onlyAgreementParty(uint256 _agreementId) {
        RentalAgreement storage ag = _agreements[_agreementId];
        require(msg.sender == ag.landlord || msg.sender == ag.tenant, "Only agreement party can perform this action");
        _;
    }

    // --- EVENTS ---
    event PropertyRegistered(uint256 indexed propertyId, address indexed landlord, string roomInfo, uint256 rentPrice, uint256 depositRequired);
    event AgreementCreated(uint256 indexed agreementId, uint256 indexed propertyId, address indexed landlord, address tenant, uint256 startTime, uint256 endTime);
    event AgreementConfirmed(uint256 indexed agreementId, address indexed confirmedBy);
    event SecurityDepositReceived(uint256 indexed agreementId, address indexed tenant, uint256 amount);
    event RentPaymentRecorded(uint256 indexed paymentId, uint256 indexed agreementId, uint256 periodIndex, uint256 amount, address indexed paidBy);
    event RoomInspected(uint256 indexed agreementId, uint256 deductionAmount, string deductionReason);
    event SecurityDepositRefunded(uint256 indexed agreementId, uint256 payoutToLandlord, uint256 refundToTenant);
    event DisputeRaised(uint256 indexed agreementId, address indexed raisedBy, string reason);
    event DisputeResolved(uint256 indexed agreementId, uint256 payoutToLandlord, uint256 refundToTenant, string resolutionNotes);

    constructor() {
        arbitrator = msg.sender; // ผู้ Deploy ทำหน้าที่เป็นตัวแทน SmartLiving Property (ผู้มีอำนาจตัดสินข้อพิพาท)
    }

    // ========================================================
    // 1. ลงทะเบียนทรัพย์สิน (Register Property)
    // ========================================================
    /**
     * @notice เจ้าของห้องสามารถสร้างรายการห้องเช่า ค่าเช่า และเงินประกัน
     */
    function registerProperty(
        string memory _roomInfo,
        uint256 _rentPrice,
        uint256 _depositRequired
    ) external returns (uint256) {
        require(bytes(_roomInfo).length > 0, "Room info cannot be empty");
        require(_rentPrice > 0, "Rent price must be greater than 0");
        require(_depositRequired > 0, "Deposit must be greater than 0");

        propertyCount++;
        uint256 newPropertyId = propertyCount;

        properties[newPropertyId] = Property({
            propertyId: newPropertyId,
            landlord: payable(msg.sender),
            roomInfo: _roomInfo,
            rentPrice: _rentPrice,
            depositRequired: _depositRequired,
            status: PropertyStatus.Available,
            exists: true
        });

        emit PropertyRegistered(newPropertyId, msg.sender, _roomInfo, _rentPrice, _depositRequired);
        return newPropertyId;
    }

    // ========================================================
    // 2. สร้างสัญญาเช่า (Create Rental Agreement)
    // ========================================================
    /**
     * @notice ระบุคู่สัญญา วันเริ่มต้น วันสิ้นสุด และเงื่อนไขสำคัญ
     */
    function createRentalAgreement(
        uint256 _propertyId,
        address payable _tenant,
        uint256 _startTime,
        uint256 _endTime,
        string memory _terms
    ) external onlyLandlord(_propertyId) returns (uint256) {
        Property storage prop = properties[_propertyId];
        require(prop.exists, "Property does not exist");
        require(prop.status == PropertyStatus.Available, "Property is not available for rent");
        require(_tenant != address(0) && _tenant != msg.sender, "Invalid tenant address");
        require(_startTime < _endTime, "Start time must be before end time");
        require(bytes(_terms).length > 0, "Terms cannot be empty");

        agreementCount++;
        uint256 newAgreementId = agreementCount;

        _agreements[newAgreementId] = RentalAgreement({
            agreementId: newAgreementId,
            propertyId: _propertyId,
            landlord: payable(msg.sender),
            tenant: _tenant,
            rentPrice: prop.rentPrice,
            depositRequired: prop.depositRequired,
            depositBalance: 0,
            startTime: _startTime,
            endTime: _endTime,
            terms: _terms,
            landlordConfirmed: true, // เจ้าของห้องยืนยันอัตโนมัติจากการเป็นผู้สร้างสัญญา
            tenantConfirmed: false,
            status: AgreementStatus.Created,
            exists: true
        });

        emit AgreementCreated(newAgreementId, _propertyId, msg.sender, _tenant, _startTime, _endTime);
        return newAgreementId;
    }

    // ========================================================
    // 3. ยืนยันสัญญา (Confirm Agreement)
    // ========================================================
    /**
     * @notice ผู้เช่าและเจ้าของห้องยืนยันการยอมรับเงื่อนไขด้วย Wallet ของตน
     */
    function confirmAgreement(uint256 _agreementId) external onlyAgreementParty(_agreementId) {
        RentalAgreement storage ag = _agreements[_agreementId];
        require(ag.exists, "Agreement does not exist");
        require(ag.status == AgreementStatus.Created, "Agreement cannot be confirmed in current status");

        if (msg.sender == ag.landlord) {
            require(!ag.landlordConfirmed, "Landlord already confirmed");
            ag.landlordConfirmed = true;
        } else if (msg.sender == ag.tenant) {
            require(!ag.tenantConfirmed, "Tenant already confirmed");
            ag.tenantConfirmed = true;
        }

        emit AgreementConfirmed(_agreementId, msg.sender);

        // เมื่อทั้งสองฝ่ายยืนยันครบถ้วน จะเปลี่ยนสถานะเป็น Confirmed
        if (ag.landlordConfirmed && ag.tenantConfirmed) {
            ag.status = AgreementStatus.Confirmed;
        }
    }

    // ========================================================
    // 4. ฝากเงินประกัน (Deposit Security)
    // ========================================================
    /**
     * @notice ผู้เช่าโอนเงินประกันในรูปแบบ ETH เข้าสู่ Smart Contract
     */
    function depositSecurity(uint256 _agreementId) external payable nonReentrant {
        RentalAgreement storage ag = _agreements[_agreementId];
        require(ag.exists, "Agreement does not exist");
        require(msg.sender == ag.tenant, "Only tenant can deposit security");
        require(ag.status == AgreementStatus.Confirmed, "Both parties must confirm agreement first");
        require(msg.value == ag.depositRequired, "Deposit amount must exactly match agreement");
        require(ag.depositBalance == 0, "Deposit has already been paid");

        // บันทึกยอดเงินประกันและเปิดใช้งานสัญญา (Active)
        ag.depositBalance = msg.value;
        ag.status = AgreementStatus.Active;
        properties[ag.propertyId].status = PropertyStatus.Rented;

        emit SecurityDepositReceived(_agreementId, msg.sender, msg.value);
    }

    // ========================================================
    // 5. บันทึกค่าเช่า (Record Rental Payment)
    // ========================================================
    /**
     * @notice ผู้เช่าชำระค่าเช่า และบันทึกประวัติธุรกรรมของแต่ละงวด
     */
    function recordRentalPayment(uint256 _agreementId) external payable nonReentrant {
        RentalAgreement storage ag = _agreements[_agreementId];
        require(ag.exists, "Agreement does not exist");
        require(msg.sender == ag.tenant, "Only tenant can pay rent");
        require(ag.status == AgreementStatus.Active, "Agreement is not currently active");
        require(msg.value == ag.rentPrice, "Payment must equal exact rent price");

        paymentCount++;
        uint256 periodIdx = agreementPaymentHistory[_agreementId].length + 1;

        // บันทึกประวัติธุรกรรมค่าเช่าแต่ละงวด
        agreementPaymentHistory[_agreementId].push(RentalPaymentRecord({
            paymentId: paymentCount,
            agreementId: _agreementId,
            periodIndex: periodIdx,
            amount: msg.value,
            paidTimestamp: block.timestamp,
            paidBy: msg.sender
        }));

        // โอนค่าเช่าให้เจ้าของห้องทันที (Checks-Effects-Interactions)
        (bool success, ) = ag.landlord.call{value: msg.value}("");
        require(success, "Transfer rent to landlord failed");

        emit RentPaymentRecorded(paymentCount, _agreementId, periodIdx, msg.value, msg.sender);
    }

    // ========================================================
    // 6. ตรวจสภาพห้องและคืนเงินประกัน (Inspection & Refund Deposit)
    // ========================================================
    /**
     * @notice ตรวจสภาพห้องเมื่อสิ้นสุดสัญญา: เจ้าของห้องบันทึกผลตรวจและยอดหักเงินประกัน (ถ้ามี)
     * กฎ: การหักเงินประกันต้องมีเหตุผล และไม่เกินยอดเงินประกันคงเหลือ
     */
    function recordRoomInspection(
        uint256 _agreementId,
        uint256 _deductionAmount,
        string memory _deductionReason
    ) external onlyAgreementParty(_agreementId) {
        RentalAgreement storage ag = _agreements[_agreementId];
        require(msg.sender == ag.landlord, "Only landlord can submit room inspection report");
        require(ag.status == AgreementStatus.Active, "Agreement must be active to inspect");
        require(_deductionAmount <= ag.depositBalance, "Deduction cannot exceed held deposit balance");

        if (_deductionAmount > 0) {
            require(bytes(_deductionReason).length > 0, "Reason must be provided for any deduction");
        }

        inspectionResults[_agreementId] = InspectionResult({
            isInspected: true,
            deductionAmount: _deductionAmount,
            deductionReason: _deductionReason,
            tenantAgreed: (_deductionAmount == 0) // หากไม่หักเงิน ให้ถือว่ายอมรับอัตโนมัติ
        });

        ag.status = AgreementStatus.Inspected;

        emit RoomInspected(_agreementId, _deductionAmount, _deductionReason);
    }

    /**
     * @notice ผู้เช่ายืนยันยอมรับผลการหักเงินประกัน (กรณีมีค่าเสียหาย)
     */
    function agreeToInspectionDeduction(uint256 _agreementId) external {
        RentalAgreement storage ag = _agreements[_agreementId];
        require(msg.sender == ag.tenant, "Only tenant can accept deduction");
        require(ag.status == AgreementStatus.Inspected, "Inspection not yet recorded");
        InspectionResult storage insp = inspectionResults[_agreementId];
        require(insp.isInspected, "Inspection not completed");

        insp.tenantAgreed = true;
    }

    /**
     * @notice คืนเงินประกันตามยอดที่ได้รับอนุมัติ (เมื่อผ่านการตรวจสภาพห้องแล้ว)
     * กฎ: คืนเงินตามยอดที่อนุมัติ และต้องไม่สามารถคืนเงินเกินยอดคงเหลือของเงินประกัน
     */
    function refundDeposit(uint256 _agreementId) external nonReentrant {
        RentalAgreement storage ag = _agreements[_agreementId];
        require(ag.status == AgreementStatus.Inspected, "Must be inspected before refund");
        InspectionResult storage insp = inspectionResults[_agreementId];
        require(insp.isInspected, "Inspection not recorded");
        require(insp.tenantAgreed, "Tenant has not agreed to deduction. If disputed, raise dispute");

        uint256 deduction = insp.deductionAmount;
        uint256 totalDeposit = ag.depositBalance;
        require(deduction <= totalDeposit, "Cannot refund more than remaining deposit");

        uint256 refundToTenant = totalDeposit - deduction;

        // ปรับสถานะและยอดคงเหลือเป็น 0 ก่อนโอนเงิน (Checks-Effects-Interactions)
        ag.depositBalance = 0;
        ag.status = AgreementStatus.Completed;
        properties[ag.propertyId].status = PropertyStatus.Available; // คืนห้องว่างให้เช่าต่อได้

        // โอนเงินค่าเสียหายให้เจ้าของห้อง (ถ้ามี)
        if (deduction > 0) {
            (bool payLandlord, ) = ag.landlord.call{value: deduction}("");
            require(payLandlord, "Transfer deduction to landlord failed");
        }

        // โอนเงินประกันส่วนที่เหลือคืนให้ผู้เช่า
        if (refundToTenant > 0) {
            (bool payTenant, ) = ag.tenant.call{value: refundToTenant}("");
            require(payTenant, "Refund deposit to tenant failed");
        }

        emit SecurityDepositRefunded(_agreementId, deduction, refundToTenant);
    }

    // ========================================================
    // 7. จัดการข้อโต้แย้ง (Rental Dispute)
    // ========================================================
    /**
     * @notice คู่สัญญา (ผู้เช่าหรือเจ้าของห้อง) ยื่นข้อโต้แย้งกรณีมีข้อพิพาทเรื่องความเสียหายหรือเงินประกัน
     */
    function raiseDispute(uint256 _agreementId, string memory _disputeReason) external onlyAgreementParty(_agreementId) {
        RentalAgreement storage ag = _agreements[_agreementId];
        require(ag.status == AgreementStatus.Active || ag.status == AgreementStatus.Inspected, "Cannot raise dispute in current status");
        require(ag.depositBalance > 0, "No deposit balance remaining to dispute");
        require(!disputeRecords[_agreementId].isDisputed, "Dispute already active");
        require(bytes(_disputeReason).length > 0, "Dispute reason is required");

        ag.status = AgreementStatus.Disputed;

        disputeRecords[_agreementId] = DisputeRecord({
            isDisputed: true,
            raisedBy: msg.sender,
            disputeReason: _disputeReason,
            raisedTimestamp: block.timestamp,
            isResolved: false,
            payoutToLandlord: 0,
            refundToTenant: 0,
            resolutionNotes: ""
        });

        emit DisputeRaised(_agreementId, msg.sender, _disputeReason);
    }

    /**
     * @notice ผู้มีอำนาจ (Arbitrator / SmartLiving Admin) พิจารณาข้อพิพาทและบันทึกผลการตัดสินก่อนปล่อยเงิน
     * กฎ: ยอดรวมที่ปล่อยต้องเท่ากับยอดเงินประกันคงเหลือพอดี (ไม่เกินยอดคงเหลือ)
     */
    function resolveDispute(
        uint256 _agreementId,
        uint256 _payoutToLandlord,
        uint256 _refundToTenant,
        string memory _resolutionNotes
    ) external onlyArbitrator nonReentrant {
        RentalAgreement storage ag = _agreements[_agreementId];
        require(ag.status == AgreementStatus.Disputed, "Agreement is not in dispute");
        DisputeRecord storage dispute = disputeRecords[_agreementId];
        require(dispute.isDisputed && !dispute.isResolved, "Dispute does not exist or already resolved");

        uint256 totalDeposit = ag.depositBalance;
        // กฎเหล็ก: ผลรวมเงินที่ปล่อยต้องเท่ากับยอดเงินประกันคงเหลือ และไม่เกินยอดคงเหลือ
        require(_payoutToLandlord + _refundToTenant == totalDeposit, "Total payouts must equal exact held deposit balance");

        // บันทึกผลการตัดสิน
        dispute.isResolved = true;
        dispute.payoutToLandlord = _payoutToLandlord;
        dispute.refundToTenant = _refundToTenant;
        dispute.resolutionNotes = _resolutionNotes;

        // เคลียร์ยอดเงินและปรับสถานะเป็น Completed
        ag.depositBalance = 0;
        ag.status = AgreementStatus.Completed;
        properties[ag.propertyId].status = PropertyStatus.Available;

        // ปล่อยเงินตามผลการตัดสิน (CEI Pattern)
        if (_payoutToLandlord > 0) {
            (bool successLandlord, ) = ag.landlord.call{value: _payoutToLandlord}("");
            require(successLandlord, "Transfer to landlord failed");
        }

        if (_refundToTenant > 0) {
            (bool successTenant, ) = ag.tenant.call{value: _refundToTenant}("");
            require(successTenant, "Transfer to tenant failed");
        }

        emit DisputeResolved(_agreementId, _payoutToLandlord, _refundToTenant, _resolutionNotes);
    }

    // ========================================================
    // VIEW FUNCTIONS (ตรวจสอบข้อมูลและประวัติธุรกรรมย้อนหลัง)
    // ========================================================

    /**
     * @notice ดูประวัติการชำระค่าเช่าทั้งหมดของแต่ละสัญญา
     */
    function getRentalPaymentHistory(uint256 _agreementId) external view returns (RentalPaymentRecord[] memory) {
        return agreementPaymentHistory[_agreementId];
    }

    /**
     * @notice ดูข้อมูลทรัพย์สิน
     */
    function getProperty(uint256 _propertyId) external view returns (Property memory) {
        return properties[_propertyId];
    }

    /**
     * @notice ดูข้อมูลสัญญาเช่า
     */
    function getAgreement(uint256 _agreementId) external view returns (RentalAgreement memory) {
        return _agreements[_agreementId];
    }

    /**
     * @notice ดูข้อมูลข้อพิพาท
     */
    function getDispute(uint256 _agreementId) external view returns (DisputeRecord memory) {
        return disputeRecords[_agreementId];
    }

    /**
     * @notice ตรวจสอบยอดเงิน ETH รวมที่ถืออยู่ใน Smart Contract
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
