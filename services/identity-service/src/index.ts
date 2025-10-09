import express, { Request, Response, NextFunction } from "express";
import jwt, { JwtHeader } from "jsonwebtoken";
import jwksRsa from "jwks-rsa";
import type { KeycloakClaims, KeycloakUser } from "@clinic/shared/types";
import { decodeToken, hasClientRole } from "@clinic/shared/auth";

const app = express();
app.use(express.json());

const KEYCLOAK_BASE_URL =
	process.env.KEYCLOAK_BASE_URL || "http://keycloak:8080";
const REALM = process.env.REALM || "clinic-mouzaia-hub";
const IDENTITY_SERVICE_CLIENT_ID =
	process.env.IDENTITY_SERVICE_CLIENT_ID || "identity-service";
const IDENTITY_SERVICE_CLIENT_SECRET =
	process.env.IDENTITY_SERVICE_CLIENT_SECRET || "EXAMPLE_REPLACE_ME";
const TRUST_GATEWAY =
	(process.env.TRUST_GATEWAY ?? "true").toLowerCase() !== "false";
const PORT = Number(process.env.IDENTITY_SERVICE_PORT || 4000);

const jwksClient = jwksRsa({
	jwksUri: `${KEYCLOAK_BASE_URL}/realms/${REALM}/protocol/openid-connect/certs`,
	cache: true,
});

async function getSigningKey(kid: string): Promise<string> {
	const key = await jwksClient.getSigningKey(kid);
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	const anyKey = key as any;
	return anyKey.getPublicKey
		? anyKey.getPublicKey()
		: anyKey.publicKey || anyKey.rsaPublicKey;
}

let adminAccessToken: string | null = null;
let adminTokenExpiresAt = 0;

async function getAdminToken(): Promise<string> {
	const now = Date.now();
	if (adminAccessToken && now < adminTokenExpiresAt - 60_000)
		return adminAccessToken;

	const resp = await fetch(
		`${KEYCLOAK_BASE_URL}/realms/${REALM}/protocol/openid-connect/token`,
		{
			method: "POST",
			headers: { "Content-Type": "application/x-www-form-urlencoded" },
			body: new URLSearchParams({
				grant_type: "client_credentials",
				client_id: IDENTITY_SERVICE_CLIENT_ID,
				client_secret: IDENTITY_SERVICE_CLIENT_SECRET,
			}),
		}
	);

	if (!resp.ok)
		throw new Error(`Failed to obtain admin token (${resp.status})`);
	const data = (await resp.json()) as {
		access_token: string;
		expires_in: number;
	};
	adminAccessToken = data.access_token;
	adminTokenExpiresAt = Date.now() + (data.expires_in ?? 60) * 1000;
	return adminAccessToken;
}

function bearerFromAuthHeader(req: Request): string | null {
	const auth = req.headers.authorization || "";
	const [scheme, token] = auth.split(" ");
	return scheme?.toLowerCase() === "bearer" && token ? token : null;
}

async function verifyJwtIfNeeded(
	token: string
): Promise<KeycloakClaims | null> {
	if (TRUST_GATEWAY) return decodeToken(token);

	const decodedComplete = jwt.decode(token, { complete: true });
	if (!decodedComplete || typeof decodedComplete === "string") return null;
	const header = decodedComplete.header as JwtHeader & { kid?: string };
	if (!header.kid) return null;

	const publicKey = await getSigningKey(header.kid);
	try {
		return jwt.verify(token, publicKey, {
			algorithms: ["RS256"],
			issuer: `${KEYCLOAK_BASE_URL}/realms/${REALM}`,
		}) as KeycloakClaims;
	} catch {
		return null;
	}
}

async function auth(req: Request, res: Response, next: NextFunction) {
	const token = bearerFromAuthHeader(req);
	if (!token) return res.status(401).json({ error: "missing_token" });
	const claims = await verifyJwtIfNeeded(token);
	if (!claims) return res.status(401).json({ error: "invalid_token" });
	(req as any).claims = claims;
	return next();
}

app.get("/health", (_req, res) => res.json({ status: "ok" }));

app.get("/users", auth, async (req, res) => {
	const claims = (req as any).claims as KeycloakClaims;
	if (!hasClientRole(claims, IDENTITY_SERVICE_CLIENT_ID, "read_users")) {
		return res.status(403).json({ error: "forbidden" });
	}

	try {
		const adminToken = await getAdminToken();
		const resp = await fetch(
			`${KEYCLOAK_BASE_URL}/admin/realms/${REALM}/users`,
			{
				headers: { Authorization: `Bearer ${adminToken}` },
			}
		);
		if (!resp.ok) return res.status(502).json({ error: "upstream_error" });

		const raw = (await resp.json()) as Array<{
			id: string;
			username: string;
			email?: string;
			firstName?: string;
			lastName?: string;
		}>;

		const users: KeycloakUser[] = raw.map((u) => ({
			id: u.id,
			username: u.username,
			email: u.email,
			firstName: u.firstName,
			lastName: u.lastName,
		}));

		return res.json(users);
	} catch (err) {
		return res
			.status(500)
			.json({ error: "server_error", message: (err as Error).message });
	}
});

app.listen(PORT, () =>
	console.log(`identity-service listening on port ${PORT}`)
);
