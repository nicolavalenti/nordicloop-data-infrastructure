-- =============================================================
-- Nordic Loop — Inventory Intelligence Platform
-- PostgreSQL Schema v1.0
-- =============================================================
-- Domain: B2B surplus material management for construction
-- and property companies. Materials flow through:
--   1. AI classification (YOLO → LLM validation → CO2 attribution)
--   2. Internal circulation (reuse within same org)
--   3. External circulation (marketplace between orgs)
-- =============================================================


-- -------------------------------------------------------------
-- ENUMS
-- -------------------------------------------------------------

CREATE TYPE user_role AS ENUM ('admin', 'member');
CREATE TYPE member_status AS ENUM ('invited', 'active', 'deactivated');
CREATE TYPE material_status AS ENUM (
    'draft',            -- uploaded, not yet classified
    'classified',       -- AI pipeline complete
    'available',        -- visible for matching
    'internally_matched',
    'externally_listed',
    'externally_matched',
    'disposed',
    'archived'
);
CREATE TYPE match_status AS ENUM ('proposed', 'accepted', 'rejected', 'completed');
CREATE TYPE listing_status AS ENUM ('active', 'sold', 'withdrawn');
CREATE TYPE wishlist_status AS ENUM ('pending', 'notified', 'fulfilled', 'expired');
CREATE TYPE llm_validation_decision AS ENUM ('confirmed', 'overridden', 'rejected');
CREATE TYPE condition_grade AS ENUM ('new', 'good', 'fair', 'poor');


-- -------------------------------------------------------------
-- ORGANISATIONS
-- -------------------------------------------------------------

CREATE TABLE organisations (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(255) NOT NULL,
    org_number          VARCHAR(50),                    -- Swedish org number e.g. 556000-0000
    industry            VARCHAR(100),                   -- e.g. 'construction', 'property_management'
    city                VARCHAR(100),
    country             VARCHAR(100) DEFAULT 'Sweden',
    created_at          TIMESTAMP DEFAULT NOW(),
    updated_at          TIMESTAMP DEFAULT NOW()
);


-- -------------------------------------------------------------
-- USERS & ORG MEMBERSHIP
-- -------------------------------------------------------------

CREATE TABLE users (
    id                  SERIAL PRIMARY KEY,
    org_id              INT NOT NULL REFERENCES organisations(id),
    email               VARCHAR(255) NOT NULL UNIQUE,
    full_name           VARCHAR(255) NOT NULL,
    role                user_role NOT NULL DEFAULT 'member',
    status              member_status NOT NULL DEFAULT 'invited',
    invited_by          INT REFERENCES users(id),       -- null for primary contact (admin)
    invited_at          TIMESTAMP,
    joined_at           TIMESTAMP,
    created_at          TIMESTAMP DEFAULT NOW(),
    updated_at          TIMESTAMP DEFAULT NOW()
);

-- Index: look up all users in an org
CREATE INDEX idx_users_org_id ON users(org_id);


-- -------------------------------------------------------------
-- PROJECTS
-- A project is a construction site or property where materials
-- are consumed or generated. Belongs to one org.
-- -------------------------------------------------------------

CREATE TABLE projects (
    id                  SERIAL PRIMARY KEY,
    org_id              INT NOT NULL REFERENCES organisations(id),
    name                VARCHAR(255) NOT NULL,
    location            VARCHAR(255),
    start_date          DATE,
    end_date            DATE,
    is_active           BOOLEAN DEFAULT TRUE,
    created_by          INT REFERENCES users(id),
    created_at          TIMESTAMP DEFAULT NOW(),
    updated_at          TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_projects_org_id ON projects(org_id);


-- -------------------------------------------------------------
-- CATEGORIES
-- Hierarchical: top-level categories + subcategories.
-- ai_supported = false for subcategories (current limitation).
-- -------------------------------------------------------------

CREATE TABLE categories (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    parent_id           INT REFERENCES categories(id),  -- null = top-level
    ai_supported        BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMP DEFAULT NOW()
);

-- Top-level categories (ai_supported = TRUE)
INSERT INTO categories (id, name, parent_id, ai_supported) VALUES
(1,  'Seating',               NULL, TRUE),
(2,  'Worksurfaces',          NULL, TRUE),
(3,  'Storage',               NULL, TRUE),
(4,  'Partitions',            NULL, TRUE),
(5,  'Flooring',              NULL, TRUE),
(6,  'Ceiling',               NULL, TRUE),
(7,  'Doors',                 NULL, TRUE),
(8,  'Construction Materials',NULL, TRUE),
(9,  'Other / Unknown',       NULL, TRUE);

-- Subcategories (ai_supported = FALSE — manual classification only for now)
INSERT INTO categories (id, name, parent_id, ai_supported) VALUES
-- Seating (parent: 1)
(10, 'Office Chairs',             1, FALSE),
(11, 'Task Chairs',               1, FALSE),
(12, 'Meeting Chairs',            1, FALSE),
(13, 'Sofas & Lounge',            1, FALSE),
(14, 'Benches',                   1, FALSE),
(15, 'Stools',                    1, FALSE),
(16, 'Armchairs',                 1, FALSE),
(17, 'Bar Chairs',                1, FALSE),
(18, 'Outdoor Seating',           1, FALSE),
(19, 'Stacking Chairs',           1, FALSE),
-- Worksurfaces (parent: 2)
(20, 'Desks',                     2, FALSE),
(21, 'Standing Desks',            2, FALSE),
(22, 'Meeting Tables',            2, FALSE),
(23, 'Conference Tables',         2, FALSE),
(24, 'Reception Counters',        2, FALSE),
(25, 'Workbenches',               2, FALSE),
(26, 'Canteen Tables',            2, FALSE),
(27, 'Side Tables',               2, FALSE),
(28, 'Kitchen Countertops',       2, FALSE),
(29, 'Tabletops',                 2, FALSE),
-- Storage (parent: 3)
(30, 'Filing Cabinets',           3, FALSE),
(31, 'Lockers',                   3, FALSE),
(32, 'Shelving Units',            3, FALSE),
(33, 'Bookcases',                 3, FALSE),
(34, 'Pedestals',                 3, FALSE),
(35, 'Wardrobes',                 3, FALSE),
(36, 'Pallet Racking',            3, FALSE),
(37, 'Mobile Shelving',           3, FALSE),
(38, 'Display Cabinets',          3, FALSE),
(39, 'Drawer Units',              3, FALSE),
-- Partitions (parent: 4)
(40, 'Office Screens',            4, FALSE),
(41, 'Glass Partitions',          4, FALSE),
(42, 'Acoustic Panels',           4, FALSE),
(43, 'Room Dividers',             4, FALSE),
(44, 'Modular Walls',             4, FALSE),
(45, 'Curtain Walls',             4, FALSE),
(46, 'Glazed Screens',            4, FALSE),
(47, 'Folding Walls',             4, FALSE),
(48, 'Privacy Screens',           4, FALSE),
(49, 'Cubicle Systems',           4, FALSE),
-- Flooring (parent: 5)
(50, 'Carpet Tiles',              5, FALSE),
(51, 'Vinyl Flooring',            5, FALSE),
(52, 'Laminate',                  5, FALSE),
(53, 'Hardwood / Parquet',        5, FALSE),
(54, 'Ceramic Tiles',             5, FALSE),
(55, 'Concrete Screed',           5, FALSE),
(56, 'Raised Access Floor',       5, FALSE),
(57, 'Rubber Flooring',           5, FALSE),
(58, 'Epoxy Coating',             5, FALSE),
(59, 'Stone / Marble',            5, FALSE),
-- Ceiling (parent: 6)
(60, 'Suspended Ceiling Tiles',   6, FALSE),
(61, 'Acoustic Ceiling Panels',   6, FALSE),
(62, 'Plasterboard Ceilings',     6, FALSE),
(63, 'Ventilation Grilles',       6, FALSE),
(64, 'Grid Systems',              6, FALSE),
(65, 'Wooden Slat Ceilings',      6, FALSE),
(66, 'Metal Ceilings',            6, FALSE),
(67, 'Stretch Ceilings',          6, FALSE),
(68, 'Lighting Tracks',           6, FALSE),
(69, 'Insulation Boards',         6, FALSE),
-- Doors (parent: 7)
(70, 'Interior Doors',            7, FALSE),
(71, 'Fire Doors',                7, FALSE),
(72, 'Glass Doors',               7, FALSE),
(73, 'Sliding Doors',             7, FALSE),
(74, 'Entrance Doors',            7, FALSE),
(75, 'Steel Security Doors',      7, FALSE),
(76, 'Acoustic Doors',            7, FALSE),
(77, 'Bi-fold Doors',             7, FALSE),
(78, 'Door Frames',               7, FALSE),
(79, 'Hardware & Fittings',       7, FALSE),
-- Construction Materials (parent: 8)
(80, 'Bricks & Blocks',           8, FALSE),
(81, 'Roof Tiles',                8, FALSE),
(82, 'Steel Beams & Profiles',    8, FALSE),
(83, 'Timber & Lumber',           8, FALSE),
(84, 'Concrete & Cement',         8, FALSE),
(85, 'Insulation',                8, FALSE),
(86, 'Facade Panels & Cladding',  8, FALSE),
(87, 'Pipes & Ducting',           8, FALSE),
(88, 'Rebar & Mesh',              8, FALSE),
(89, 'Sand & Aggregates',         8, FALSE),
(90, 'Window Frames',             8, FALSE),
(91, 'Scaffolding',               8, FALSE),
(92, 'Fixings & Fasteners',       8, FALSE),
(93, 'Waterproofing & Membranes', 8, FALSE),
-- Other / Unknown (parent: 9)
(94, 'Mixed Lot',                 9, FALSE),
(95, 'Electrical Components',     9, FALSE),
(96, 'Plumbing Fixtures',         9, FALSE),
(97, 'HVAC Components',           9, FALSE),
(98, 'Lighting',                  9, FALSE),
(99, 'Signage',                   9, FALSE),
(100,'Outdoor / Landscaping',     9, FALSE),
(101,'Unidentified Material',     9, FALSE);


-- -------------------------------------------------------------
-- MATERIAL ITEMS
-- The atomic unit. One physical surplus item at a location.
-- Belongs to a project (and therefore an org).
-- -------------------------------------------------------------

CREATE TABLE material_items (
    id                  SERIAL PRIMARY KEY,
    org_id              INT NOT NULL REFERENCES organisations(id),
    project_id          INT REFERENCES projects(id),
    uploaded_by         INT REFERENCES users(id),

    -- Basic description
    title               VARCHAR(255),
    description         TEXT,
    quantity            DECIMAL(10, 2) NOT NULL DEFAULT 1,
    unit                VARCHAR(50),                    -- 'pcs', 'm2', 'kg', 'lm'
    condition_grade     condition_grade,
    estimated_value_sek DECIMAL(10, 2),

    -- Category (set after AI classification)
    category_id         INT REFERENCES categories(id),
    subcategory_id      INT REFERENCES categories(id),

    -- Lifecycle
    status              material_status NOT NULL DEFAULT 'draft',

    -- Image
    image_url           TEXT,

    created_at          TIMESTAMP DEFAULT NOW(),
    updated_at          TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_material_items_org_id ON material_items(org_id);
CREATE INDEX idx_material_items_status ON material_items(status);
CREATE INDEX idx_material_items_category ON material_items(category_id);


-- -------------------------------------------------------------
-- AI CLASSIFICATIONS
-- Records the full pipeline output for each material item:
-- YOLO → LLM validation → final category.
-- One row per classification attempt (retries are new rows).
-- -------------------------------------------------------------

CREATE TABLE ai_classifications (
    id                      SERIAL PRIMARY KEY,
    material_item_id        INT NOT NULL REFERENCES material_items(id),

    -- YOLO output
    yolo_predicted_category_id  INT REFERENCES categories(id),
    yolo_confidence_score       DECIMAL(5, 4),          -- 0.0000 – 1.0000

    -- LLM validation layer
    llm_decision                llm_validation_decision,
    llm_reasoning               TEXT,                   -- LLM's explanation
    llm_suggested_category_id   INT REFERENCES categories(id),  -- only if overridden

    -- Final resolved category (after pipeline)
    final_category_id           INT REFERENCES categories(id),

    -- Pipeline metadata
    model_version               VARCHAR(50),            -- e.g. 'yolov7-nl-v2'
    classified_at               TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_ai_classifications_item ON ai_classifications(material_item_id);


-- -------------------------------------------------------------
-- CO2 ATTRIBUTIONS
-- Derived from classification. Records the environmental value
-- of reusing a material item instead of procuring new.
-- -------------------------------------------------------------

CREATE TABLE co2_attributions (
    id                      SERIAL PRIMARY KEY,
    material_item_id        INT NOT NULL REFERENCES material_items(id),
    ai_classification_id    INT REFERENCES ai_classifications(id),

    -- CO2 calculation
    co2_saved_kg            DECIMAL(10, 3),             -- kg CO2e saved if reused
    co2_methodology         VARCHAR(100),               -- e.g. 'EPD', 'ICE_DB', 'internal_v1'
    calculation_notes       TEXT,

    created_at              TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_co2_attributions_item ON co2_attributions(material_item_id);


-- -------------------------------------------------------------
-- INTERNAL MATCHES
-- A material item redeployed to another project within the
-- same org. Scoped strictly to org_id — no cross-org access.
-- -------------------------------------------------------------

CREATE TABLE internal_matches (
    id                      SERIAL PRIMARY KEY,
    org_id                  INT NOT NULL REFERENCES organisations(id),
    material_item_id        INT NOT NULL REFERENCES material_items(id),

    source_project_id       INT REFERENCES projects(id),    -- where item came from
    destination_project_id  INT REFERENCES projects(id),    -- where item is going

    requested_by            INT REFERENCES users(id),
    approved_by             INT REFERENCES users(id),

    status                  match_status NOT NULL DEFAULT 'proposed',
    co2_saved_kg            DECIMAL(10, 3),             -- copied from co2_attribution at match time

    proposed_at             TIMESTAMP DEFAULT NOW(),
    completed_at            TIMESTAMP
);

CREATE INDEX idx_internal_matches_org_id ON internal_matches(org_id);
CREATE INDEX idx_internal_matches_item ON internal_matches(material_item_id);


-- -------------------------------------------------------------
-- EXTERNAL LISTINGS
-- When no internal match exists, an item is listed on the
-- external marketplace. Visible to other orgs.
-- -------------------------------------------------------------

CREATE TABLE external_listings (
    id                      SERIAL PRIMARY KEY,
    material_item_id        INT NOT NULL REFERENCES material_items(id),
    org_id                  INT NOT NULL REFERENCES organisations(id),  -- seller org

    asking_price_sek        DECIMAL(10, 2),
    status                  listing_status NOT NULL DEFAULT 'active',

    listed_by               INT REFERENCES users(id),
    listed_at               TIMESTAMP DEFAULT NOW(),
    sold_at                 TIMESTAMP,
    withdrawn_at            TIMESTAMP
);

CREATE INDEX idx_external_listings_status ON external_listings(status);
CREATE INDEX idx_external_listings_org ON external_listings(org_id);


-- -------------------------------------------------------------
-- EXTERNAL MATCHES
-- A transaction between two orgs via the marketplace.
-- -------------------------------------------------------------

CREATE TABLE external_matches (
    id                      SERIAL PRIMARY KEY,
    listing_id              INT NOT NULL REFERENCES external_listings(id),
    material_item_id        INT NOT NULL REFERENCES material_items(id),

    seller_org_id           INT NOT NULL REFERENCES organisations(id),
    buyer_org_id            INT NOT NULL REFERENCES organisations(id),
    buyer_user_id           INT REFERENCES users(id),

    agreed_price_sek        DECIMAL(10, 2),
    status                  match_status NOT NULL DEFAULT 'proposed',
    co2_saved_kg            DECIMAL(10, 3),

    proposed_at             TIMESTAMP DEFAULT NOW(),
    completed_at            TIMESTAMP
);

CREATE INDEX idx_external_matches_seller ON external_matches(seller_org_id);
CREATE INDEX idx_external_matches_buyer ON external_matches(buyer_org_id);


-- -------------------------------------------------------------
-- WISHLISTS
-- Demand signals. A user subscribes to a category and gets
-- notified when a matching item surfaces (internally or externally).
-- -------------------------------------------------------------

CREATE TABLE wishlists (
    id                      SERIAL PRIMARY KEY,
    user_id                 INT NOT NULL REFERENCES users(id),
    org_id                  INT NOT NULL REFERENCES organisations(id),

    category_id             INT NOT NULL REFERENCES categories(id),
    subcategory_id          INT REFERENCES categories(id),  -- optional, more specific
    notes                   TEXT,                           -- free text, e.g. "min 10 units, good condition"

    status                  wishlist_status NOT NULL DEFAULT 'pending',
    notified_at             TIMESTAMP,
    fulfilled_by_item_id    INT REFERENCES material_items(id),  -- set when fulfilled

    created_at              TIMESTAMP DEFAULT NOW(),
    updated_at              TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_wishlists_user ON wishlists(user_id);
CREATE INDEX idx_wishlists_org ON wishlists(org_id);
CREATE INDEX idx_wishlists_category ON wishlists(category_id);
