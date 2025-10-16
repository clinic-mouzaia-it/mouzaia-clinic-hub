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

	const allowed = hasClientRole(
		claims,
		"pharmacy-service",
		"allowed_to_see_medicines"
	);
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
			"pharmacy-service",
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

app.patch(
	"/pharmacy/medicines/:id",
	async (
		req: Request<{ id: string }, {}, Prisma.MedicineUpdateInput>,
		res: Response
	) => {
		const token = bearerFromAuthHeader(req);
		if (!token) return res.status(401).json({ error: "missing_token" });

		const claims = decodeToken(token);
		if (!claims) return res.status(401).json({ error: "invalid_token" });

		const allowed = hasClientRole(
			claims,
			"pharmacy-service",
			"allowed_to_update_medicines"
		);
		if (!allowed) return res.status(403).json({ error: "forbidden" });

		const { id } = req.params;
		try {
			// Prevent updating DB-generated or controlled fields
			const forbidden = ["id", "deleted", "createdAt", "updatedAt"] as const;
			for (const f of forbidden) {
				if (Object.prototype.hasOwnProperty.call(req.body || {}, f)) {
					return res.status(400).json({
						error: "invalid_update_field",
						field: f,
						message: `Field '${f}' cannot be updated`,
					});
				}
			}

			// Reject empty update payloads
			if (!req.body || Object.keys(req.body).length === 0) {
				return res.status(400).json({ error: "empty_update" });
			}

			// If the medicine is deleted, require a special role to allow updates
			const current = await prisma.medicine.findUnique({
				where: { id },
				select: { deleted: true },
			});
			if (!current) {
				return res.status(404).json({ error: "medicine_not_found" });
			}
			if (current.deleted) {
				const canUpdateDeleted = hasClientRole(
					claims,
					"pharmacy-service",
					"allowed_to_update_deleted_medicines"
				);
				if (!canUpdateDeleted) {
					return res.status(403).json({ error: "forbidden_deleted_update" });
				}
			}
			const updated = await prisma.medicine.update({
				where: { id },
				data: req.body,
			});
			return res.json(updated);
		} catch (err: any) {
			// Map not-found to 404; other validation errors to 400
			if (err?.code === "P2025") {
				return res.status(404).json({ error: "medicine_not_found" });
			}
			return res
				.status(400)
				.json({ error: "invalid_update", message: err?.message });
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
			"pharmacy-service",
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

app.get("/pharmacy/medicines/deleted", async (req: Request, res: Response) => {
	const token = bearerFromAuthHeader(req);
	if (!token) return res.status(401).json({ error: "missing_token" });

	const claims = decodeToken(token);
	if (!claims) return res.status(401).json({ error: "invalid_token" });

	const allowed = hasClientRole(
		claims,
		"pharmacy-service",
		"allowed_to_see_deleted_medicines"
	);
	if (!allowed) return res.status(403).json({ error: "forbidden" });

	try {
		const deletedMedicines = await prisma.medicine.findMany({
			where: { deleted: true },
			orderBy: { updatedAt: "desc" },
		});
		return res.json(deletedMedicines);
	} catch (err) {
		return res
			.status(500)
			.json({ error: "database_error", message: (err as Error).message });
	}
});

app.patch(
	"/pharmacy/medicines/:id/restore",
	async (req: Request, res: Response) => {
		const token = bearerFromAuthHeader(req);
		if (!token) return res.status(401).json({ error: "missing_token" });

		const claims = decodeToken(token);
		if (!claims) return res.status(401).json({ error: "invalid_token" });

		const allowed = hasClientRole(
			claims,
			"pharmacy-service",
			"allowed_to_restore_deleted_medicines"
		);
		if (!allowed) return res.status(403).json({ error: "forbidden" });

		const { id } = req.params;

		try {
			// First check if the medicine exists and is deleted
			const existingMedicine = await prisma.medicine.findUnique({
				where: { id },
			});

			if (!existingMedicine) {
				return res.status(404).json({ error: "medicine_not_found" });
			}

			if (!existingMedicine.deleted) {
				return res.status(400).json({
					error: "medicine_not_deleted",
					message: "This medicine is not marked as deleted",
				});
			}

			// Restore the medicine by setting deleted to false
			const restoredMedicine = await prisma.medicine.update({
				where: { id },
				data: { deleted: false },
			});

			return res.json({
				success: true,
				message: "Medicine restored successfully",
				medicine: restoredMedicine,
			});
		} catch (err) {
			return res
				.status(500)
				.json({ error: "database_error", message: (err as Error).message });
		}
	}
);

app.post(
	"/pharmacy/medicines/distribute",
	async (req: Request, res: Response) => {
		const token = bearerFromAuthHeader(req);
		if (!token) return res.status(401).json({ error: "missing_token" });

		const claims = decodeToken(token);
		if (!claims) return res.status(401).json({ error: "invalid_token" });

		const allowed = hasClientRole(
			claims,
			"pharmacy-service",
			"allowed_to_distribute_medicine"
		);
		if (!allowed) return res.status(403).json({ error: "forbidden" });

		const { staffUser, medicines } = req.body;

		if (!staffUser || !medicines || !Array.isArray(medicines)) {
			return res.status(400).json({ error: "missing_required_fields" });
		}

		if (medicines.length === 0) {
			return res.status(400).json({ error: "no_medicines_to_distribute" });
		}

		// Validate staffUser has required fields
		if (
			!staffUser.id ||
			!staffUser.username ||
			!staffUser.nationalId ||
			!staffUser.roleMappings
		) {
			return res.status(400).json({ error: "invalid_staff_user_data" });
		}

		// Check if staff user has allowed_to_take_medicines role
		const clientMappings = staffUser.roleMappings?.clientMappings || {};
		// Keycloak's role-mappings response keys client mappings by clientId.
		// Our clientId is 'pharmacy-service'.
		const pharmacyClientMapping = clientMappings["pharmacy-service"];
		const pharmacyRoles = pharmacyClientMapping?.mappings || [];
		const hasPermission = pharmacyRoles.some(
			(role: { name: string }) => role.name === "allowed_to_take_medicines"
		);

		if (!hasPermission) {
			return res.status(403).json({
				error: "staff_not_allowed_to_take_medicines",
				message: `Staff member ${staffUser.username} does not have permission to receive medicines`,
			});
		}

		try {
			// Validate all medicines and check stock
			const medicineIds = medicines.map((m: { id: string }) => m.id);
			const dbMedicines = await prisma.medicine.findMany({
				where: { id: { in: medicineIds }, deleted: false },
			});

			if (dbMedicines.length !== medicines.length) {
				return res.status(404).json({ error: "some_medicines_not_found" });
			}

			// Check stock for all medicines
			for (const requestedMed of medicines) {
				const dbMed = dbMedicines.find((m) => m.id === requestedMed.id);
				if (!dbMed) {
					return res.status(404).json({
						error: "medicine_not_found",
						medicineId: requestedMed.id,
					});
				}
				if (dbMed.stock < requestedMed.quantity) {
					return res.status(400).json({
						error: "insufficient_stock",
						medicineName: dbMed.nomCommercial,
						available: dbMed.stock,
						requested: requestedMed.quantity,
					});
				}
			}

			const staffFullName = staffUser.firstName
				? `${staffUser.firstName} ${staffUser.lastName || ""}`.trim()
				: staffUser.username;

			const distributorName = claims.preferred_username || claims.sub;

			// Create distributions and update stock in a transaction
			const results = await prisma.$transaction(async (tx) => {
				const distributions = [];

				for (const requestedMed of medicines) {
					const dbMed = dbMedicines.find((m) => m.id === requestedMed.id);
					if (!dbMed) continue; // Already validated above, but TypeScript safety

					// Create distribution record
					const distribution = await tx.distribution.create({
						data: {
							medicineId: requestedMed.id,
							medicineName: dbMed.nomCommercial,
							quantity: requestedMed.quantity,
							staffUserId: staffUser.id,
							staffUsername: staffUser.username,
							staffNationalId: staffUser.nationalId,
							staffFullName: staffFullName,
							distributedBy: distributorName,
						},
					});

					// Update medicine stock
					await tx.medicine.update({
						where: { id: requestedMed.id },
						data: {
							stock: {
								decrement: requestedMed.quantity,
							},
						},
					});

					distributions.push(distribution);
				}

				return distributions;
			});

			return res.json({
				success: true,
				message: `Successfully distributed ${medicines.length} medicine(s) to ${staffFullName}`,
				distributions: results,
			});
		} catch (err) {
			return res
				.status(500)
				.json({ error: "server_error", message: (err as Error).message });
		}
	}
);

app.listen(PORT, () =>
	console.log(`pharmacy-service listening on port ${PORT}`)
);
