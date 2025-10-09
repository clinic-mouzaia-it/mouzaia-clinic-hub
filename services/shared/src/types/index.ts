export interface KeycloakResourceAccess {
  [clientId: string]: { roles: string[] } | undefined;
}

export interface KeycloakClaims {
  sub: string;
  preferred_username?: string;
  email?: string;
  azp?: string;
  scope?: string;
  resource_access?: KeycloakResourceAccess;
  realm_access?: { roles: string[] };
  iss?: string;
  aud?: string | string[];
}

export interface KeycloakUser {
  id: string;
  username: string;
  email?: string;
  firstName?: string;
  lastName?: string;
}

export interface VerifyStaffRequestDTO {
  national_id: string;
}

export interface VerifyStaffResponseDTO {
  ok: boolean;
  userId?: string;
  reason?: string;
}
