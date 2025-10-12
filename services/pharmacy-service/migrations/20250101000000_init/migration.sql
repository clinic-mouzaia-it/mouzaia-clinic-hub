-- CreateTable
CREATE TABLE "medicines" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "DCI" TEXT NOT NULL,
    "nom_commercial" TEXT NOT NULL,
    "STOCK" INTEGER NOT NULL DEFAULT 0,
    "DDP" TEXT,
    "LOT" TEXT,
    "COUT" DECIMAL(10,2) NOT NULL,
    "PRIX_DE_VENTE" DECIMAL(10,2) NOT NULL,
    "deleted" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "medicines_pkey" PRIMARY KEY ("id")
);
