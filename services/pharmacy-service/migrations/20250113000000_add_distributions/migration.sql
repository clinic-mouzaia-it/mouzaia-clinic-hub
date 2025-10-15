-- CreateTable
CREATE TABLE "distributions" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "medicine_id" UUID NOT NULL,
    "medicine_name" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL DEFAULT 1,
    "staff_user_id" TEXT NOT NULL,
    "staff_username" TEXT NOT NULL,
    "staff_national_id" TEXT NOT NULL,
    "staff_full_name" TEXT,
    "distributed_by" TEXT NOT NULL,
    "distributed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "distributions_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "distributions_quantity_min" CHECK ("quantity" >= 1)
);

-- AddForeignKey
ALTER TABLE "distributions" ADD CONSTRAINT "distributions_medicine_id_fkey" FOREIGN KEY ("medicine_id") REFERENCES "medicines"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
