import { vi } from 'vitest';

const QRCode = {
  toCanvas: vi.fn(async (canvas, text, options) => {
    // Mock successful QR code generation
    canvas.innerHTML = '<mock-qr-code></mock-qr-code>';
  })
};

export default QRCode;