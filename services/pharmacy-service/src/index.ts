import express, { Request, Response } from "express";
import { decodeToken } from "@clinic/shared/auth";

const app = express();
app.use(express.json());

const PORT = Number(process.env.PHARMACY_SERVICE_PORT || 4100);
const IDENTITY_BASE =
	process.env.IDENTITY_BASE_URL || "http://identity-service:4000";

function bearerFromAuthHeader(req: Request): string | null {
	const auth = req.headers.authorization || "";
	const [scheme, token] = auth.split(" ");
	return scheme?.toLowerCase() === "bearer" && token ? token : null;
}

app.get("/health", (_req, res) => res.json({ status: "ok" }));

app.post("/pharmacy/verify-staff", async (req: Request, res: Response) => {
	const token = bearerFromAuthHeader(req);
	if (!token) return res.status(401).json({ error: "missing_token" });

	const claims = decodeToken(token);
	if (!claims) return res.status(401).json({ error: "invalid_token" });

	try {
		const resp = await fetch(`${IDENTITY_BASE}/users?debug=1`, {
			headers: { Authorization: `Bearer ${token}` },
		});
		const data = await resp.json();
		return res.json({ ok: true, staffData: data });
	} catch (err) {
		return res.status(502).json({ ok: false, error: (err as Error).message });
	}
});

app.get("/pharmacy/medicines", (_req, res) => {
	res.json([
		{ id: "med-001", name: "Paracetamol 500mg", stock: 120 },
		{ id: "med-002", name: "Ibuprofen 200mg", stock: 75 },
	]);
});

app.listen(PORT, () =>
	console.log(`pharmacy-service listening on port ${PORT}`)
);
