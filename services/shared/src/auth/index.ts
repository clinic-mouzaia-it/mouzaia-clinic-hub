import type { KeycloakClaims } from "../types";

export function decodeToken(token: string): KeycloakClaims | null {
  try {
    // lightweight decode without verification; consumers must trust gateway or verify elsewhere
    const parts = token.split(".");
    if (parts.length < 2) return null;
    const payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const json = Buffer.from(payload, "base64").toString("utf8");
    return JSON.parse(json) as KeycloakClaims;
  } catch {
    return null;
  }
}

export function hasClientRole(
  claims: KeycloakClaims | undefined,
  clientId: string,
  role: string
): boolean {
  const roles = claims?.resource_access?.[clientId]?.roles || [];
  return roles.includes(role);
}

export function hasRealmRole(
  claims: KeycloakClaims | undefined,
  role: string
): boolean {
  const roles = claims?.realm_access?.roles || [];
  return roles.includes(role);
}
