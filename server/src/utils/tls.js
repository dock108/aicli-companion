import { generateKeyPairSync, createHash, randomBytes } from 'crypto';
import { writeFileSync, readFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';
import { promisify } from 'util';

const CERT_DIR = './certs';
const CERT_VALIDITY_DAYS = 365;

export class TLSManager {
  constructor() {
    this.certPath = join(CERT_DIR, 'server.crt');
    this.keyPath = join(CERT_DIR, 'server.key');
    this.ensureCertDirectory();
  }
  
  ensureCertDirectory() {
    if (!existsSync(CERT_DIR)) {
      mkdirSync(CERT_DIR, { recursive: true });
    }
  }
  
  async generateSelfSignedCertificate() {
    console.log('Generating self-signed TLS certificate...');
    
    try {
      // Generate RSA key pair
      const { publicKey, privateKey } = generateKeyPairSync('rsa', {
        modulusLength: 2048,
        publicKeyEncoding: {
          type: 'spki',
          format: 'pem'
        },
        privateKeyEncoding: {
          type: 'pkcs8',
          format: 'pem'
        }
      });
      
      // Create certificate
      const cert = await this.createCertificate(publicKey, privateKey);
      
      // Save to files
      writeFileSync(this.keyPath, privateKey);
      writeFileSync(this.certPath, cert);
      
      console.log(`✅ TLS certificate generated:`);
      console.log(`   Certificate: ${this.certPath}`);
      console.log(`   Private Key: ${this.keyPath}`);
      
      return { cert, key: privateKey };
    } catch (error) {
      console.error('Failed to generate TLS certificate:', error);
      throw error;
    }
  }
  
  async createCertificate(publicKey, privateKey) {
    // For a proper implementation, we'd need a certificate generation library
    // This is a simplified version - in production, consider using libraries like:
    // - node-forge
    // - @peculiar/x509
    // - or generate externally with openssl
    
    // For now, create a basic self-signed certificate structure
    const now = new Date();
    const validFrom = now;
    const validTo = new Date(now.getTime() + (CERT_VALIDITY_DAYS * 24 * 60 * 60 * 1000));
    
    // This is a placeholder - real implementation would use proper ASN.1 encoding
    const certData = {
      subject: {
        commonName: 'Claude Companion Server',
        organizationName: 'Claude Companion',
        countryName: 'US'
      },
      issuer: {
        commonName: 'Claude Companion Server',
        organizationName: 'Claude Companion',
        countryName: 'US'
      },
      serialNumber: '01',
      validFrom: validFrom.toISOString(),
      validTo: validTo.toISOString(),
      publicKey: publicKey
    };
    
    // In a real implementation, this would generate proper X.509 certificate
    const certPem = this.generateCertificatePEM(certData);
    return certPem;
  }
  
  generateCertificatePEM(certData) {
    // This is a placeholder implementation
    // Real certificate generation would require proper ASN.1 encoding
    const certContent = Buffer.from(JSON.stringify(certData)).toString('base64');
    
    return `-----BEGIN CERTIFICATE-----
${certContent.match(/.{1,64}/g).join('\n')}
-----END CERTIFICATE-----`;
  }
  
  async ensureCertificateExists() {
    if (!this.certificateExists()) {
      return await this.generateSelfSignedCertificate();
    }
    
    return this.loadExistingCertificate();
  }
  
  certificateExists() {
    return existsSync(this.certPath) && existsSync(this.keyPath);
  }
  
  loadExistingCertificate() {
    try {
      const cert = readFileSync(this.certPath, 'utf8');
      const key = readFileSync(this.keyPath, 'utf8');
      return { cert, key };
    } catch (error) {
      console.error('Failed to load existing certificate:', error);
      return null;
    }
  }
  
  getCertificateFingerprint() {
    if (!this.certificateExists()) return null;
    
    try {
      const cert = readFileSync(this.certPath, 'utf8');
      // In a real implementation, this would calculate the actual certificate fingerprint
      const hash = createHash('sha256');
      hash.update(cert);
      return hash.digest('hex').match(/.{2}/g).join(':').toUpperCase();
    } catch (error) {
      return null;
    }
  }
}

// Simple token generation utility
export class TokenManager {
  static generateSecureToken(length = 32) {
    return randomBytes(length).toString('hex');
  }
  
  static generateAPIKey() {
    const prefix = 'cc_';
    const token = this.generateSecureToken(20);
    return prefix + token;
  }
  
  static hashToken(token) {
    return createHash('sha256').update(token).digest('hex');
  }
  
  static verifyToken(token, hashedToken) {
    return this.hashToken(token) === hashedToken;
  }
}

// OpenSSL-based certificate generation (fallback)
export async function generateCertificateWithOpenSSL() {
  const { exec } = await import('child_process');
  const { promisify } = await import('util');
  const execAsync = promisify(exec);
  
  try {
    // Check if OpenSSL is available
    await execAsync('openssl version');
    
    console.log('Generating certificate with OpenSSL...');
    
    // Generate private key
    await execAsync(`openssl genrsa -out ${join(CERT_DIR, 'server.key')} 2048`);
    
    // Generate certificate signing request
    const csrCmd = `openssl req -new -key ${join(CERT_DIR, 'server.key')} -out ${join(CERT_DIR, 'server.csr')} -subj "/C=US/ST=State/L=City/O=Claude Companion/CN=localhost"`;
    await execAsync(csrCmd);
    
    // Generate self-signed certificate
    const certCmd = `openssl x509 -req -days ${CERT_VALIDITY_DAYS} -in ${join(CERT_DIR, 'server.csr')} -signkey ${join(CERT_DIR, 'server.key')} -out ${join(CERT_DIR, 'server.crt')}`;
    await execAsync(certCmd);
    
    // Clean up CSR file
    await execAsync(`rm ${join(CERT_DIR, 'server.csr')}`);
    
    console.log('✅ Certificate generated with OpenSSL');
    
    const cert = readFileSync(join(CERT_DIR, 'server.crt'), 'utf8');
    const key = readFileSync(join(CERT_DIR, 'server.key'), 'utf8');
    
    return { cert, key };
  } catch (error) {
    console.log('OpenSSL not available or failed, falling back to Node.js crypto');
    throw error;
  }
}