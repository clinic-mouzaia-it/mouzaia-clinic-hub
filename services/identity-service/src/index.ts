import express, { Request, Response, NextFunction } from "express";
import jwt, { JwtHeader } from "jsonwebtoken";
import jwksRsa from "jwks-rsa";
import type { KeycloakClaims, KeycloakUser } from "./types";

// Express app for identity-service.
// Defaults assume running behind Kong Gateway. If TRUST_GATEWAY=false, we validate JWTs locally.

const app = express();
app.use(express.json());

// Environment variables with defaults
const KEYCLOAK_BASE_URL =
	process.env.KEYCLOAK_BASE_URL || "http://keycloak:8080";
const REALM = process.env.REALM || "clinic-mouzaia-hub";
const SERVICE_CLIENT_ID = process.env.SERVICE_CLIENT_ID || "identity-service";
// EXAMPLE_REPLACE_ME: Replace SERVICE_CLIENT_SECRET with the real client secret in deployment
const SERVICE_CLIENT_SECRET =
	process.env.SERVICE_CLIENT_SECRET || "EXAMPLE_REPLACE_ME";
const TRUST_GATEWAY =
	(process.env.TRUST_GATEWAY ?? "true").toLowerCase() !== "false";
const IDENTITY_SERVICE_PORT = Number(process.env.IDENTITY_SERVICE_PORT || 4000);

// JWKS client for local JWT verification (only used when TRUST_GATEWAY=false)
const jwksClient = jwksRsa({
	jwksUri: `${KEYCLOAK_BASE_URL}/realms/${REALM}/protocol/openid-connect/certs`,
	cache: true,
	cacheMaxEntries: 5,
	cacheMaxAge: 10 * 60 * 1000,
});

async function getSigningKey(kid: string): Promise<string> {
	const key = await jwksClient.getSigningKey(kid);
	// Prefer publicKey but fall back to rsaPublicKey
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	const anyKey = key as any;
	return anyKey.getPublicKey
		? anyKey.getPublicKey()
		: anyKey.publicKey || anyKey.rsaPublicKey;
}

// Admin token cache for Keycloak client credentials flow
let adminAccessToken: string | null = null;
let adminTokenExpiresAt = 0; // epoch ms

async function getAdminToken(): Promise<string> {
	const now = Date.now();
	if (adminAccessToken && now < adminTokenExpiresAt - 60_000) {
		return adminAccessToken;
	}

	const tokenUrl = `${KEYCLOAK_BASE_URL}/realms/${REALM}/protocol/openid-connect/token`;
	const body = new URLSearchParams();
	body.set("grant_type", "client_credentials");
	body.set("client_id", SERVICE_CLIENT_ID);
	body.set("client_secret", SERVICE_CLIENT_SECRET);

	const resp = await fetch(tokenUrl, {
		method: "POST",
		headers: { "Content-Type": "application/x-www-form-urlencoded" },
		body,
	});
	if (!resp.ok) {
		const text = await resp.text().catch(() => "");
		throw new Error(`Failed to obtain admin token (${resp.status}): ${text}`);
	}
	const data = (await resp.json()) as {
		access_token: string;
		expires_in: number;
	};
	adminAccessToken = data.access_token;
	adminTokenExpiresAt = Date.now() + (data.expires_in ?? 60) * 1000;
	return adminAccessToken;
}

// Helpers
function bearerFromAuthHeader(req: Request): string | null {
	const auth = req.headers.authorization || "";
	const [scheme, token] = auth.split(" ");
	if (scheme?.toLowerCase() === "bearer" && token) return token;
	return null;
}

function hasClientRole(
	claims: KeycloakClaims | undefined,
	clientId: string,
	role: string
): boolean {
	const roles = claims?.resource_access?.[clientId]?.roles || [];
	return roles.includes(role);
}

async function verifyJwtIfNeeded(
	token: string
): Promise<KeycloakClaims | null> {
	if (TRUST_GATEWAY) {
		// Behind Kong Gateway: decode only (Kong Gateway should have validated already)
		const decoded = jwt.decode(token) as KeycloakClaims | null;
		return decoded;
	}

	const decodedComplete = jwt.decode(token, { complete: true });
	if (!decodedComplete || typeof decodedComplete === "string") return null;
	const header = decodedComplete.header as JwtHeader & { kid?: string };
	const kid = header.kid;
	if (!kid) return null;
	const publicKey = await getSigningKey(kid);
	try {
		const verified = jwt.verify(token, publicKey, {
			algorithms: ["RS256"],
			issuer: `${KEYCLOAK_BASE_URL}/realms/${REALM}`,
		}) as KeycloakClaims;
		return verified;
	} catch {
		return null;
	}
}

// Authentication middleware: extracts and validates/decodes JWT
async function auth(req: Request, res: Response, next: NextFunction) {
	const token = bearerFromAuthHeader(req);
	if (!token) return res.status(401).json({ error: "missing_token" });
	const claims = await verifyJwtIfNeeded(token);
	if (!claims) return res.status(401).json({ error: "invalid_token" });
	// attach to request
	(req as unknown as { claims: KeycloakClaims }).claims = claims;
	return next();
}

app.get("/health", (_req: Request, res: Response) => {
	res.status(200).json({ status: "ok" });
});

// DEBUG endpoint: echoes headers and token info to verify KrakenD forwarding
app.get("/debug-token", (req: Request, res: Response) => {
	const authHeader = req.headers.authorization || "(none)";
	let decoded: unknown = null;

	if (authHeader.startsWith("Bearer ")) {
		const token = authHeader.slice("Bearer ".length);
		try {
			decoded = jwt.decode(token);
		} catch (err) {
			decoded = { error: (err as Error).message };
		}
	}

	console.log("=== /debug-token called ===");
	console.log("Headers:", req.headers);

	res.status(200).json({
		message: "Debug endpoint hit",
		authHeader,
		decoded,
		headers: req.headers,
	});
});

// GET /users - requires client role read_users under identity-service
// app.get("/users", auth, async (req: Request, res: Response) => {
// 	const claims = (req as unknown as { claims: KeycloakClaims }).claims;
// 	if (!hasClientRole(claims, SERVICE_CLIENT_ID, "read_users")) {
// 		return res.status(403).json({ error: "forbidden" });
// 	}

// 	try {
// 		const adminToken = await getAdminToken();
// 		const usersUrl = `${KEYCLOAK_BASE_URL}/admin/realms/${REALM}/users`;
// 		const resp = await fetch(usersUrl, {
// 			headers: { Authorization: `Bearer ${adminToken}` },
// 		});
// 		if (!resp.ok) {
// 			const text = await resp.text().catch(() => "");
// 			return res.status(502).json({ error: "upstream_error", details: text });
// 		}
// 		// Keycloak user representation is broad; select safe fields
// 		const raw = (await resp.json()) as Array<{
// 			id: string;
// 			username: string;
// 			email?: string;
// 			firstName?: string;
// 			lastName?: string;
// 		}>;
// 		const sanitized: KeycloakUser[] = raw.map((u) => ({
// 			id: u.id,
// 			username: u.username,
// 			email: u.email,
// 			firstName: u.firstName,
// 			lastName: u.lastName,
// 		}));
// 		return res.json(sanitized);
// 	} catch (err) {
// 		return res
// 			.status(500)
// 			.json({ error: "server_error", message: (err as Error).message });
// 	}
// });

// GET /users - requires client role read_users under identity-service
app.get("/users", auth, async (req: Request, res: Response) => {
	const claims = (req as unknown as { claims: KeycloakClaims }).claims;

	console.log("=== /users called ===");
	console.log(
		"Decoded claims (krakend forwarded):",
		JSON.stringify(claims, null, 2)
	);

	const hasReadUsers = hasClientRole(claims, SERVICE_CLIENT_ID, "read_users");
	console.log(
		`hasClientRole(${SERVICE_CLIENT_ID}, read_users) => ${hasReadUsers}`
	);

	// Short-circuit debug: do not call Keycloak if debug query param supplied
	if (req.query.debug === "1") {
		return res.status(200).json({
			debug: true,
			ok: hasReadUsers,
			message: hasReadUsers
				? "caller has read_users role (debug mode)"
				: "caller missing read_users role (debug mode)",
			claims_preview: {
				sub: claims?.sub,
				preferred_username: claims?.preferred_username,
				resource_access: claims?.resource_access,
			},
		});
	}

	// Enforce service-role check at service level
	if (!hasReadUsers) {
		console.warn(
			"Forbidden: caller does not have identity-service client role 'read_users'"
		);
		return res
			.status(403)
			.json({ error: "forbidden", reason: "missing_client_role:read_users" });
	}

	try {
		const adminToken = await getAdminToken();
		console.log("Obtained admin token (length):", adminToken?.length ?? null);

		const usersUrl = `${KEYCLOAK_BASE_URL}/admin/realms/${REALM}/users`;
		const resp = await fetch(usersUrl, {
			headers: { Authorization: `Bearer ${adminToken}` },
		});

		console.log(`/admin/users upstream status: ${resp.status}`);

		if (!resp.ok) {
			const text = await resp.text().catch(() => "");
			console.error("Upstream Keycloak error:", resp.status, text);
			return res.status(502).json({ error: "upstream_error", details: text });
		}

		const raw = (await resp.json()) as Array<{
			id: string;
			username: string;
			email?: string;
			firstName?: string;
			lastName?: string;
		}>;

		const sanitized: KeycloakUser[] = raw.map((u) => ({
			id: u.id,
			username: u.username,
			email: u.email,
			firstName: u.firstName,
			lastName: u.lastName,
		}));

		// Successful response
		return res.json(sanitized);
	} catch (err) {
		console.error("Server error in /users:", (err as Error).message);
		return res
			.status(500)
			.json({ error: "server_error", message: (err as Error).message });
	}
});

app.listen(IDENTITY_SERVICE_PORT, () => {
	// eslint-disable-next-line no-console
	console.log(`identity-service listening on port ${IDENTITY_SERVICE_PORT}`);
});
