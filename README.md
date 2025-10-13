# Clinic Mouzaia Hub

A microservices-based clinic management system with role-based access control (RBAC), API gateway, and PostgreSQL databases.

## Architecture

The system follows a microservices architecture with the following components:

- **Keycloak**: Identity and access management (IAM) server for authentication and authorization
- **KrakenD**: API Gateway for routing, rate limiting, and JWT validation
- **Traefik**: Reverse proxy for SSL/TLS termination and routing
- **PostgreSQL**: Database for each microservice
- **Identity Service**: User management service
- **Pharmacy Service**: Medicine inventory management service

### Technology Stack

- **Runtime**: Node.js 20 (Alpine Linux)
- **Language**: TypeScript
- **Database**: PostgreSQL 16
- **ORM**: Prisma
- **API Gateway**: KrakenD
- **Auth**: Keycloak (OpenID Connect / OAuth2)
- **Reverse Proxy**: Traefik
- **Container**: Docker & Docker Compose

## Project Structure

```
mouzaia-clinic-hub/
├── keycloak/
│   ├── Dockerfile
│   └── clinic-mouzaia-hub-realm.json        # Realm configuration with clients, roles, users
├── krakend/
│   ├── Dockerfile
│   └── krakend.json                         # API Gateway endpoints and routing
├── postgres/
│   ├── Dockerfile
│   ├── pg_hba.conf
│   └── postgresql.conf
├── services/
│   ├── identity-service/
│   │   ├── src/
│   │   │   └── index.ts
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── tsconfig.json
│   ├── pharmacy-service/
│   │   ├── migrations/
│   │   │   └── 20250101000000_init/
│   │   │       └── migration.sql            # DB schema with CHECK constraints
│   │   ├── src/
│   │   │   └── index.ts                     # REST API endpoints
│   │   ├── schema.prisma                    # Prisma schema for medicines
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   └── tsconfig.json
│   ├── shared/
│   │   ├── src/
│   │   │   ├── auth/
│   │   │   │   └── index.ts                 # JWT decode & role checking utilities
│   │   │   └── types/
│   │   │       └── index.ts                 # Shared TypeScript types
│   │   ├── package.json
│   │   └── tsconfig.json
│   ├── package.json                         # Root workspace package.json
│   ├── package-lock.json
│   └── tsconfig.base.json
├── traefik/
│   ├── Dockerfile
│   ├── traefik.yaml
│   └── dynamic.yaml
├── test/
│   ├── test-add-medicines.sh                # Test: Add medicines
│   ├── test-add-medicines-edge-cases.sh     # Test: Add medicines validation
│   ├── test-soft-delete-medicines.sh        # Test: Soft delete medicines
│   ├── test-see-medicines.sh                # Test: List medicines
│   ├── test-pharmacy-medicines.sh           # Test: Pharmacy endpoints
│   └── test-users.sh                        # Test: Identity service
├── docker-compose.yml                       # Service orchestration
├── example.env                              # Environment variables template
├── run.sh                                   # Build and deployment script
└── README.md
```

## Services

### Pharmacy Service

Manages medicine inventory with the following features:
- Create medicines (POST)
- List medicines (GET) - excludes soft-deleted items
- Soft delete medicines (DELETE)

**Database Schema** (`medicines` table):
- `id` (UUID, Primary Key)
- `dci` (Text, Required) - International Nonproprietary Name
- `nomCommercial` (Text, Required) - Commercial name
- `stock` (Integer, Default: 0, CHECK: >= 0)
- `ddp` (Text, Optional) - Expiry date
- `lot` (Text, Optional) - Batch number
- `cout` (Decimal(10,2), Required, CHECK: > 0) - Cost price
- `prixDeVente` (Decimal(10,2), Required, CHECK: > 0) - Selling price
- `deleted` (Boolean, Default: false) - Soft delete flag
- `createdAt` (Timestamp)
- `updatedAt` (Timestamp)

**Endpoints**:
- `GET /pharmacy/medicines` - List all non-deleted medicines
- `POST /pharmacy/medicines` - Create a new medicine
- `DELETE /pharmacy/medicines/{id}/soft-delete` - Soft delete a medicine

### Identity Service

Manages user information and integrates with Keycloak.

**Endpoints**:
- `GET /users` - List users (requires `read_users` role)
- `POST /pharmacy/verify-staff` - Verify staff member

## Roles & Permissions

### Keycloak Clients

1. **krakend-gateway**
   - `api_user` - Access to protected API endpoints

2. **identity-service**
   - `read_users` - Read user information

3. **pharmacy**
   - `allowed_to_see_medicines` - View medicine inventory
   - `allowed_to_take_medicines` - Take/dispense medicines
   - `allowed_to_add_medicines` - Add new medicines to inventory
   - `allowed_to_delete_medicines` - Soft delete medicines

### Users

- **pharmacist**
  - Password: `DummyPassword123!`
  - Roles: All pharmacy roles + `api_user` + `read_users`
  
- **staff2**
  - Password: `DummyPass2!`
  - Roles: `api_user` only (limited permissions for testing)

## Getting Started

### Prerequisites

- Docker & Docker Compose
- Bash shell
- `jq` (for running test scripts)

### Environment Setup

1. Copy the example environment file:
```bash
cp example.env .env
```

2. Update `.env` with your configuration (if needed)

### Building Services

Build all services:
```bash
bash run.sh build
```

<B>OR</B> Build a specific service:
```bash
bash run.sh build pharmacy-service
bash run.sh build identity-service
```

### Deployment

Start all services:
```bash
bash run.sh up
```

Stop all services:
```bash
bash run.sh down
```

View logs:
```bash
bash run.sh logs pharmacy-service
```

### (Developement) Install Dependencies

Install dependencies for all services:
```bash
cd services
npm i
```

### (Developement) Prisma Client Generation

Regenerate Prisma client after schema changes:
```bash
cd services
npm run prisma:generate
```

## Testing

All test scripts authenticate with Keycloak and test the API endpoints through the KrakenD gateway.

### Test Scripts

#### 1. Add Medicines Test
```bash
bash test/test-add-medicines.sh
```

**What it tests:**
- Authenticates as pharmacist user
- Creates 3 test medicines:
  - Doliprane 500mg (Paracetamol)
  - Advil 400mg (Ibuprofen)
  - Amoxil 500mg (Amoxicillin)
- Validates successful creation (201 status)
- Displays created medicine details

#### 2. Add Medicines Edge Cases Test
```bash
bash test/test-add-medicines-edge-cases.sh
```

**What it tests:**
- **Authentication & Authorization:**
  - No token → 401 Unauthorized
  - Invalid token → 401 Unauthorized
  - Valid token without `allowed_to_add_medicines` role → 403 Forbidden

- **Missing Required Fields:**
  - Missing `dci` → 500 (Prisma validation error)
  - Missing `nomCommercial` → 500
  - Missing `cout` → 500
  - Missing `prixDeVente` → 500

- **Invalid Data Types:**
  - Invalid JSON payload → 400 Bad Request
  - `cout` as string → 500 (Prisma type error)
  - `stock` as string → 500

- **Database Constraints:**
  - Negative `cout` → 500 (CHECK constraint violation)
  - Negative `prixDeVente` → 500
  - Negative `stock` → 500
  - Zero `cout` → 500 (must be > 0)
  - Zero `prixDeVente` → 500 (must be > 0)
  - Zero `stock` → 201 Success (>= 0 is valid)

- **Valid Cases:**
  - Minimal payload (required fields only) → 201
  - Complete payload (all fields) → 201

#### 3. Soft Delete Medicines Test
```bash
bash test/test-soft-delete-medicines.sh
```

**What it tests:**
- Creates a test medicine
- Extracts the medicine ID from response
- Soft deletes the medicine using `DELETE /pharmacy/medicines/{id}/soft-delete`
- Verifies `deleted` field is set to `true`
- Medicine remains in database but marked as deleted

#### 4. See Medicines Test
```bash
bash test/test-see-medicines.sh
```

**What it tests:**
- **Authentication & Authorization:**
  - No token → 401
  - Invalid token → 401
  - Valid token without `allowed_to_see_medicines` role → 403

- **Valid Request:**
  - Retrieves all non-deleted medicines
  - Returns 200 with medicine array
  - Verifies no soft-deleted medicines are included
  - Displays total count

#### 5. Users Test
```bash
bash test/test-users.sh [--debug]
```

**What it tests:**
- Authenticates as pharmacist
- Calls identity service `/users` endpoint
- Validates `read_users` role requirement
- Optional `--debug` flag for detailed output

## API Endpoints

### Base URL
- API Gateway: `http://hubapi.mouzaiaclinic.local`
- Keycloak: `http://hubkeycloak.mouzaiaclinic.local`

### Authentication

All endpoints require a Bearer token obtained from Keycloak:

```bash
curl -X POST "http://hubkeycloak.mouzaiaclinic.local/realms/clinic-mouzaia-hub/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=krakend-gateway" \
  -d "username=pharmacist" \
  -d "password=DummyPassword123!"
```

### Pharmacy Endpoints

#### List Medicines
```bash
GET /pharmacy/medicines
Authorization: Bearer {token}
Required Role: pharmacy.allowed_to_see_medicines

Response: 200 OK
[
  {
    "id": "uuid",
    "dci": "Paracetamol",
    "nomCommercial": "Doliprane 500mg",
    "stock": 150,
    "ddp": "2026-12-31",
    "lot": "LOT-001",
    "cout": "2.50",
    "prixDeVente": "5.00",
    "deleted": false,
    "createdAt": "2025-10-12T10:00:00.000Z",
    "updatedAt": "2025-10-12T10:00:00.000Z"
  }
]
```

#### Create Medicine
```bash
POST /pharmacy/medicines
Authorization: Bearer {token}
Content-Type: application/json
Required Role: pharmacy.allowed_to_add_medicines

Body:
{
  "dci": "Paracetamol",
  "nomCommercial": "Doliprane 500mg",
  "stock": 150,
  "ddp": "2026-12-31",
  "lot": "LOT-001",
  "cout": 2.50,
  "prixDeVente": 5.00
}

Response: 201 Created
```

#### Soft Delete Medicine
```bash
DELETE /pharmacy/medicines/{id}/soft-delete
Authorization: Bearer {token}
Required Role: pharmacy.allowed_to_delete_medicines

Response: 200 OK
{
  "id": "uuid",
  "deleted": true,
  ...
}
```

### Identity Endpoints

#### List Users
```bash
GET /users
Authorization: Bearer {token}
Required Role: identity-service.read_users

Response: 200 OK
```

## Database Constraints

The pharmacy service enforces data integrity at the database level:

1. **Positive Prices**: `cout` and `prixDeVente` must be greater than 0
2. **Non-negative Stock**: `stock` must be >= 0 (zero is allowed)
3. **Required Fields**: `dci`, `nomCommercial`, `cout`, `prixDeVente` are mandatory
4. **UUIDs**: All IDs are UUID v4
5. **Timestamps**: Automatic `createdAt` and `updatedAt` management

## Troubleshooting

### Prisma Client Not Found

If you see TypeScript errors about missing Prisma client:
```bash
cd services
npm run prisma:generate
```

### Service Won't Start

Check logs:
```bash
bash run.sh logs pharmacy-service
```

Rebuild the service:
```bash
bash run.sh build pharmacy-service
bash run.sh up
```

### Database Migration Issues

Migrations run automatically on container startup. If issues occur:
```bash
# View migration status in service logs
bash run.sh logs pharmacy-service | grep migration
```

## Development

### Adding a New Migration

1. Update the Prisma schema in `services/pharmacy-service/schema.prisma`
2. Create a new migration directory in `services/pharmacy-service/migrations/`
3. Add the SQL migration file
4. Regenerate the Prisma client: `npm run prisma:generate`
5. Rebuild the service

### Adding a New Endpoint

1. Add the role in `keycloak/clinic-mouzaia-hub-realm.json`
2. Add the endpoint in `krakend/krakend.json` with role validation
3. Implement the handler in the service's `src/index.ts`
4. Create a test script following existing patterns
5. Update this README

## License

Private project for Clinic Mouzaia.
