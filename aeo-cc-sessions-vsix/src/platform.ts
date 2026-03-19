import * as fs from 'node:fs';

export interface PlatformInfo {
  hasProc: boolean;
  environment: 'wsl' | 'linux-native' | 'windows';
  label: string;
}

function isProcAvailable(): boolean {
  try {
    fs.accessSync('/proc/self/stat', fs.constants.R_OK);
    return true;
  } catch {
    return false;
  }
}

function isWSL(): boolean {
  try {
    const version = fs.readFileSync('/proc/version', 'utf8');
    return /microsoft/i.test(version);
  } catch {
    return false;
  }
}

export function detectPlatform(): PlatformInfo {
  const hasProc = isProcAvailable();
  if (!hasProc) {
    return { hasProc, environment: 'windows', label: 'Windows (no /proc)' };
  }
  if (isWSL()) {
    return { hasProc, environment: 'wsl', label: 'WSL' };
  }
  return { hasProc, environment: 'linux-native', label: 'Linux' };
}
