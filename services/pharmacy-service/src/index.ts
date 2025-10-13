import express, { Request, Response } from "express";
import { decodeToken, hasClientRole } from "@clinic/shared/auth";
import { PrismaClient, Prisma } from "@prisma/pharmacy-client";

const prisma = new PrismaClient();

const app = express();
app.use(express.json());

const PORT = Number(process.env.PHARMACY_SERVICE_PORT || 4100);

function bearerFromAuthHeader(req: Request): string | null {
	const auth = req.headers.authorization || "";
	const [scheme, token] = auth.split(" ");
	return scheme?.toLowerCase() === "bearer" && token ? token : null;
}

app.get("/health", (_req, res) => res.json({ status: "ok" }));

app.get("/pharmacy/medicines", async (req: Request, res: Response) => {
	const token = bearerFromAuthHeader(req);
	if (!token) return res.status(401).json({ error: "missing_token" });

	const claims = decodeToken(token);
	if (!claims) return res.status(401).json({ error: "invalid_token" });

	const allowed = hasClientRole(claims, "pharmacy", "allowed_to_see_medicines");
	if (!allowed) return res.status(403).json({ error: "forbidden" });

	try {
		const medicines = await prisma.medicine.findMany({
			where: { deleted: false },
			orderBy: { createdAt: "desc" },
		});
		return res.json(medicines);
	} catch (err) {
		return res
			.status(500)
			.json({ error: "database_error", message: (err as Error).message });
	}
});

app.post(
	"/pharmacy/medicines",
	async (req: Request<{}, {}, Prisma.MedicineCreateInput>, res: Response) => {
		const token = bearerFromAuthHeader(req);
		if (!token) return res.status(401).json({ error: "missing_token" });

		const claims = decodeToken(token);
		if (!claims) return res.status(401).json({ error: "invalid_token" });

		const allowed = hasClientRole(
			claims,
			"pharmacy",
			"allowed_to_add_medicines"
		);
		if (!allowed) return res.status(403).json({ error: "forbidden" });

		try {
			const medicine = await prisma.medicine.create({
				data: req.body,
			});
			return res.status(201).json(medicine);
		} catch (err) {
			return res
				.status(500)
				.json({ error: "database_error", message: (err as Error).message });
		}
	}
);

app.delete(
	"/pharmacy/medicines/:id/soft-delete",
	async (req: Request, res: Response) => {
		const token = bearerFromAuthHeader(req);
		if (!token) return res.status(401).json({ error: "missing_token" });

		const claims = decodeToken(token);
		if (!claims) return res.status(401).json({ error: "invalid_token" });

		const allowed = hasClientRole(
			claims,
			"pharmacy",
			"allowed_to_delete_medicines"
		);
		if (!allowed) return res.status(403).json({ error: "forbidden" });

		const { id } = req.params;

		try {
			const medicine = await prisma.medicine.update({
				where: { id },
				data: { deleted: true },
			});
			return res.json(medicine);
		} catch (err) {
			return res
				.status(500)
				.json({ error: "database_error", message: (err as Error).message });
		}
	}
);

app.listen(PORT, () =>
	console.log(`pharmacy-service listening on port ${PORT}`)
);
