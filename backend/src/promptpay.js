// สร้างข้อความสำหรับ QR พร้อมเพย์ (Thai QR Payment / EMVCo) — แอปธนาคารไทยทุกเจ้าสแกนได้
// ไม่ต้องสมัครบริการใด เงินเข้าบัญชีพร้อมเพย์ของร้านโดยตรง

/** ตรวจ/จัดรูปแบบหมายเลขพร้อมเพย์: เบอร์มือถือ 10 หลัก | เลขบัตร ปชช./ผู้เสียภาษี 13 หลัก | e-Wallet 15 หลัก */
export function normalizePromptPayId(input) {
  const digits = String(input ?? '').replace(/\D/g, '');
  if (/^0\d{9}$/.test(digits)) return digits;
  if (/^\d{13}$/.test(digits) || /^\d{15}$/.test(digits)) return digits;
  return null;
}

/** แสดงผลแบบปิดบางส่วน เช่น 081-xxx-5678 (ให้ลูกค้าเช็คว่าโอนถูกร้าน) */
export function maskPromptPayId(id) {
  if (!id) return null;
  if (id.length === 10) return `${id.slice(0, 3)}-xxx-${id.slice(6)}`;
  return `${id.slice(0, 1)}-xxxx-xxxxx-${id.slice(-3, -1)}-${id.slice(-1)}`;
}

const tlv = (tag, value) => `${tag}${String(value.length).padStart(2, '0')}${value}`;

/** CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) ตามสเปก EMVCo */
function crc16(str) {
  let crc = 0xffff;
  for (const byte of Buffer.from(str, 'utf8')) {
    crc ^= byte << 8;
    for (let i = 0; i < 8; i++) crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
  }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}

/** payload ของ QR พร้อมเพย์แบบระบุยอดเงิน (dynamic QR) */
export function promptPayPayload(promptpayId, amount) {
  const id = normalizePromptPayId(promptpayId);
  if (!id) throw new Error('invalid PromptPay ID');
  const account = id.length === 10
    ? tlv('01', `0066${id.slice(1)}`)  // เบอร์มือถือ → 0066 + ตัด 0 หน้า
    : id.length === 13 ? tlv('02', id) // เลขบัตรประชาชน / ผู้เสียภาษี
      : tlv('03', id);                 // e-Wallet
  const body = [
    tlv('00', '01'),                                  // Payload format
    tlv('01', '12'),                                  // 12 = QR ใช้ครั้งเดียว (มียอดเงิน)
    tlv('29', tlv('00', 'A000000677010111') + account), // PromptPay
    tlv('53', '764'),                                 // THB
    tlv('54', Number(amount).toFixed(2)),
    tlv('58', 'TH'),
  ].join('') + '6304';
  return body + crc16(body);
}
