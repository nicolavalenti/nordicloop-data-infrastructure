# Nordic Loop — Data Infrastructure Design
### B2B AI Inventory Platform · PostgreSQL Schema + Synthetic Dataset

This repository documents the data architecture behind **Nordic Loop**, a B2B SaaS platform that helps construction and property companies manage surplus materials — reducing procurement costs and CO2 emissions through internal reuse and external resale.

It serves as a portfolio case study demonstrating schema design, domain modelling, and analytical SQL for a real product with genuine complexity.

---

## What Nordic Loop does

Construction companies generate large amounts of surplus material — furniture, flooring, doors, structural components — when projects end or offices are refitted. Nordic Loop gives these companies a structured way to:

1. **Inventory & classify** surplus across projects using AI image recognition
2. **Circulate internally** — match surplus to other projects within the same organisation before buying new
3. **Circulate externally** — list unmatched surplus on a B2B marketplace for other companies to purchase

The platform was built and shipped by a team of 7, including a trained YOLOv7 image recognition model, an LLM validation layer, and a CO2 attribution microservice.

---

## Repository contents

```
/
├── schema.sql          # Full PostgreSQL schema with enums, tables, indexes, and seeded categories
├── seed_data.sql       # 500 synthetic material items + all related records
└── README.md
```

---

## Schema overview

The schema is built around the **lifecycle of a material item** — from image upload through AI classification to one of three outcomes: internal reuse, external sale, or disposal.

```
Image upload
    └─► AI Classification (YOLOv7 → LLM validation → CO2 attribution)
            └─► available
                    ├─► Internal Match (redeployed within org)
                    ├─► External Listing → External Match (sold to another org)
                    └─► Disposed / Archived
```

### Tables

| Table | Description |
|---|---|
| `organisations` | B2B customers (construction & property companies) |
| `users` | Members of an org; role-based (admin / member) with invite flow |
| `projects` | Construction sites or properties where materials are generated or needed |
| `categories` | Hierarchical: 9 top-level + 84 subcategories; `ai_supported` flag tracks model coverage |
| `material_items` | Core entity — one physical surplus item, with full lifecycle status |
| `ai_classifications` | YOLO confidence score + LLM decision (confirmed / overridden / rejected) + final category |
| `co2_attributions` | kg CO2e saved if item is reused; methodology tagged for auditability |
| `internal_matches` | Redeployment events within a single org |
| `external_listings` | Items listed on the marketplace when no internal match exists |
| `external_matches` | Transactions between two orgs via the marketplace |
| `wishlists` | Demand signals — users subscribe to categories and get notified when supply appears |

### Key design decisions

**The org boundary is structural, not logical.**
Internal matches enforce `org_id` at the data layer. A query joining `internal_matches` to `material_items` can never accidentally return cross-org results — the constraint is in the schema, not application code.

**AI classifications are immutable append-only records.**
Each classification attempt creates a new row. This means model version improvements can be measured historically: you can compare override rates between `yolov7-nl-v1` and `yolov7-nl-v2` without losing the original predictions.

**CO2 is stored at match time, not recalculated.**
`co2_saved_kg` is copied from `co2_attributions` into `internal_matches` and `external_matches` at the moment of the transaction. This means CO2 reporting stays accurate even when the attribution methodology changes — historical records are preserved.

**Wishlists are demand signals, not just notifications.**
`fulfilled_by_item_id` links a wishlist entry to the specific material item that fulfilled it, enabling fulfillment rate analysis by category.

---

## Synthetic dataset

The seed data was generated to reflect realistic platform behaviour across a 14-month period (September 2023 – November 2024).

| Entity | Count |
|---|---|
| Organisations | 8 |
| Users | 45 |
| Projects | 34 |
| Material items | 500 |
| AI classifications | 468 |
| CO2 attributions | 426 |
| Internal matches | 94 |
| External listings | 120 |
| External matches | 46 |
| Wishlists | 60 |

Organisations are based on real Swedish construction and property companies (Skanska, NCC, Peab, Fabege, Castellum, etc.) with realistic org numbers. Material status distribution reflects a live platform: ~30% available, ~22% internally matched, ~15% externally listed, ~10% externally matched.

LLM validation decisions are distributed as: **72% confirmed**, **20% overridden**, **8% rejected** — based on expected model performance at this stage of training.

---

## Analytical queries

Some representative queries against this schema:

```sql
-- 1. LLM override rate by category
--    (how often does the LLM disagree with YOLO per material type?)
SELECT
    c.name AS category,
    COUNT(*) AS total_classified,
    SUM(CASE WHEN ac.llm_decision = 'overridden' THEN 1 ELSE 0 END) AS overrides,
    ROUND(100.0 * SUM(CASE WHEN ac.llm_decision = 'overridden' THEN 1 ELSE 0 END) / COUNT(*), 1) AS override_pct
FROM ai_classifications ac
JOIN material_items mi ON mi.id = ac.material_item_id
JOIN categories c ON c.id = mi.category_id
GROUP BY c.name
ORDER BY override_pct DESC;

-- 2. CO2 saved: internal circulation vs external
SELECT
    'internal' AS circulation_type,
    COUNT(*) AS matches,
    ROUND(SUM(co2_saved_kg)::numeric, 1) AS total_co2_kg
FROM internal_matches WHERE status = 'completed'
UNION ALL
SELECT
    'external',
    COUNT(*),
    ROUND(SUM(co2_saved_kg)::numeric, 1)
FROM external_matches WHERE status = 'completed';

-- 3. Wishlist fulfillment rate by category
SELECT
    c.name AS category,
    COUNT(*) AS total_wishlists,
    SUM(CASE WHEN w.status = 'fulfilled' THEN 1 ELSE 0 END) AS fulfilled,
    ROUND(100.0 * SUM(CASE WHEN w.status = 'fulfilled' THEN 1 ELSE 0 END) / COUNT(*), 1) AS fulfillment_pct
FROM wishlists w
JOIN categories c ON c.id = w.category_id
GROUP BY c.name
ORDER BY fulfillment_pct DESC;

-- 4. Average days from upload to internal match
SELECT
    ROUND(AVG(EXTRACT(EPOCH FROM (im.proposed_at - mi.created_at)) / 86400)::numeric, 1) AS avg_days_to_match
FROM internal_matches im
JOIN material_items mi ON mi.id = im.material_item_id;

-- 5. Supply vs demand gap by category
--    (which categories have high wishlist demand but low available inventory?)
SELECT
    c.name AS category,
    COUNT(DISTINCT mi.id) AS available_items,
    COUNT(DISTINCT w.id) AS active_wishlists,
    COUNT(DISTINCT w.id) - COUNT(DISTINCT mi.id) AS demand_gap
FROM categories c
LEFT JOIN material_items mi ON mi.category_id = c.id AND mi.status = 'available'
LEFT JOIN wishlists w ON w.category_id = c.id AND w.status = 'pending'
WHERE c.parent_id IS NULL
GROUP BY c.name
ORDER BY demand_gap DESC;
```

---

## How to run

```bash
# Create a local database and load everything
createdb nordic_loop
psql nordic_loop < schema.sql
psql nordic_loop < seed_data.sql
```

Requires PostgreSQL 13+.

---

## Context

This schema was designed as part of a broader product and data infrastructure build at Nordic Loop during its pivot from a pure marketplace to an internal inventory system with a connected external marketplace. The AI pipeline (YOLOv7 → LLM validation → CO2 attribution) is operational, with pilots running at Mod:group and Skanska.

The analytical questions this schema enables map directly to the metrics that matter at this stage: AI model quality (override rate), environmental impact (CO2 attribution), and platform health (internal vs external circulation ratio, wishlist fulfillment).
