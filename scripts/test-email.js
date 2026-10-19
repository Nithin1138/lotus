#!/usr/bin/env node
/**
 * Local Test Script for DropDial Email & License Generation
 * Usage:
 *   node scripts/test-email.js
 *   node scripts/test-email.js re_your_resend_api_key veeranithin9@gmail.com
 */

const fs = require('fs');
const path = require('path');

// Simple .env parser for local testing if .env exists
const envPath = path.join(__dirname, '../.env');
if (fs.existsSync(envPath)) {
  const content = fs.readFileSync(envPath, 'utf8');
  content.split('\n').forEach(line => {
    const match = line.match(/^\s*([\w.-]+)\s*=\s*(.*)?\s*$/);
    if (match) {
      const key = match[1];
      let value = match[2] || '';
      if (value.startsWith('"') && value.endsWith('"')) value = value.slice(1, -1);
      if (value.startsWith("'") && value.endsWith("'")) value = value.slice(1, -1);
      if (!process.env[key]) process.env[key] = value;
    }
  });
}

const { generateLicense, sendResendEmail } = require('../api/_utils');

async function main() {
  const customApiKey = process.argv[2];
  const targetEmail = process.argv[3] || 'veeranithin9@gmail.com';

  if (customApiKey && customApiKey.startsWith('re_')) {
    process.env.RESEND_API_KEY = customApiKey;
  }

  const apiKey = process.env.RESEND_API_KEY;
  console.log('----------------------------------------------------');
  console.log('DropDial Pro: Email & License Test Runner');
  console.log('----------------------------------------------------');
  console.log(`Target Email: ${targetEmail}`);
  console.log(`RESEND_API_KEY: ${apiKey ? apiKey.slice(0, 8) + '...' : '❌ NOT SET'}`);
  console.log(`RESEND_FROM_EMAIL: ${process.env.RESEND_FROM_EMAIL || 'DropDial Pro <onboarding@resend.dev>'}`);

  console.log('\n[1/2] Generating cryptographically signed ECDSA P-256 license key...');
  let licenseKey;
  try {
    licenseKey = generateLicense(targetEmail, 'Nithin', 'pro');
    console.log(`✅ License Generated: ${licenseKey}`);
  } catch (err) {
    console.error(`❌ License Generation Failed: ${err.message}`);
    process.exit(1);
  }

  console.log('\n[2/2] Sending branded HTML email via Resend API...');
  if (!apiKey) {
    console.log('⚠️  No RESEND_API_KEY found.');
    console.log('Pass it as an argument: node scripts/test-email.js re_12345678 ' + targetEmail);
    process.exit(1);
  }

  const result = await sendResendEmail({
    to: targetEmail,
    name: 'Nithin',
    licenseKey,
    paymentId: `manual_test_${Date.now()}`,
    amount: '₹999'
  });

  if (result.success) {
    console.log(`✅ Success! Email delivered to ${targetEmail}. Resend Email ID: ${result.id}`);
  } else {
    console.error('❌ Resend API Error:', JSON.stringify(result.error || result, null, 2));
  }
}

main().catch(console.error);
