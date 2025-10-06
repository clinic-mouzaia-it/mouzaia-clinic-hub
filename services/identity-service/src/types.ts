// Type definitions shared across the identity service.
// Keep interfaces minimal and aligned with typical Keycloak tokens.

export interface KeycloakClaims {
  // Issuer of the token (Keycloak realm URL)
  iss: string;
  // Subject (user id)
  sub: string;
  // Expiration and issued-at timestamps (seconds since epoch)
  exp: number;
  iat: number;
  // Common user identity fields
  preferred_username: string;
  email?: string;
  // Realm-level roles
  realm_access?: {
    roles: string[];
  };
  // Client-level roles, keyed by clientId
  resource_access?: {
    [clientId: string]: {
      roles: string[];
    };
  };
  // Allow additional, provider-specific claims
  [key: string]: unknown;
}

export interface KeycloakUser {
  id: string;
  username: string;
  email?: string;
  firstName?: string;
  lastName?: string;
  // Extendable for service-specific attributes
  [key: string]: unknown;
}
