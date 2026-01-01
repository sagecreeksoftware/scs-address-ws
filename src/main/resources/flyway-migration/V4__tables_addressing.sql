-- =====================================================================
-- postal_code_areas
-- =====================================================================
CREATE TABLE postal_code_areas (
    postal_code_id BIGSERIAL PRIMARY KEY,
    country_id BIGINT NOT NULL,
    division_id BIGINT NOT NULL,
    postal_code VARCHAR(10) NOT NULL,
    postal_code_normalized VARCHAR(10) NOT NULL,
    postal_code_prefix VARCHAR(6),
    latitude DECIMAL(10, 7),
    longitude DECIMAL(11, 7),
    location GEOGRAPHY(POINT, 4326),
    geographic_boundary GEOGRAPHY(POLYGON, 4326),
    timezone VARCHAR(50),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP ,
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP ,

    CONSTRAINT fk_postal_country FOREIGN KEY (country_id)
        REFERENCES countries(country_id) ON DELETE RESTRICT,
    CONSTRAINT fk_postal_division FOREIGN KEY (division_id)
        REFERENCES administrative_divisions(division_id) ON DELETE RESTRICT,
    CONSTRAINT uq_postal_code_country UNIQUE (country_id, postal_code_normalized),
    CONSTRAINT chk_latitude_range CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT chk_longitude_range CHECK (longitude BETWEEN -180 AND 180)
);

CREATE INDEX idx_postal_country ON postal_code_areas(country_id);
CREATE INDEX idx_postal_division ON postal_code_areas(division_id);
CREATE INDEX idx_postal_code ON postal_code_areas(postal_code_normalized);
CREATE INDEX idx_postal_prefix ON postal_code_areas(postal_code_prefix);
CREATE INDEX idx_postal_location ON postal_code_areas USING gist(location);
CREATE INDEX idx_postal_boundary ON postal_code_areas USING gist(geographic_boundary);

COMMENT ON TABLE postal_code_areas IS 'Central repository for postal/ZIP codes with geocoding and spatial data';
COMMENT ON COLUMN postal_code_areas.postal_code_prefix IS 'Forward Sortation Area (FSA) for Canada, e.g., K1A from K1A 0B1';

-- =====================================================================
-- localities
-- =====================================================================
CREATE TABLE localities (
    locality_id BIGSERIAL PRIMARY KEY,
    division_id BIGINT NOT NULL,
    postal_code_id BIGINT,
    locality_name VARCHAR(100) NOT NULL,
    locality_name_native VARCHAR(100),
    locality_type locality_type NOT NULL,
    population INTEGER,
    latitude DECIMAL(10, 7),
    longitude DECIMAL(11, 7),
    location GEOGRAPHY(POINT, 4326),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP ,
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP ,

    CONSTRAINT fk_locality_division FOREIGN KEY (division_id)
        REFERENCES administrative_divisions(division_id) ON DELETE RESTRICT,
    CONSTRAINT fk_locality_postal FOREIGN KEY (postal_code_id)
        REFERENCES postal_code_areas(postal_code_id) ON DELETE SET NULL,
    CONSTRAINT chk_population_positive CHECK (population IS NULL OR population >= 0)
);

CREATE INDEX idx_locality_division ON localities(division_id);
CREATE INDEX idx_locality_postal ON localities(postal_code_id);
CREATE INDEX idx_locality_name ON localities(locality_name);
CREATE INDEX idx_locality_name_trgm ON localities USING gin(locality_name gin_trgm_ops);
CREATE INDEX idx_locality_type ON localities(locality_type);
CREATE INDEX idx_locality_location ON localities USING gist(location);

COMMENT ON TABLE localities IS 'Cities, towns, villages, and other populated places';

-- =====================================================================
-- streets
-- =====================================================================
CREATE TABLE streets (
    street_id BIGSERIAL PRIMARY KEY,
    locality_id BIGINT NOT NULL,
    postal_code_id BIGINT,
    street_name VARCHAR(100) NOT NULL,
    street_name_normalized VARCHAR(100) NOT NULL,
    street_type VARCHAR(30),
    street_direction VARCHAR(5),
    is_active BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP ,
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP ,

    CONSTRAINT fk_street_locality FOREIGN KEY (locality_id)
        REFERENCES localities(locality_id) ON DELETE RESTRICT,
    CONSTRAINT fk_street_postal FOREIGN KEY (postal_code_id)
        REFERENCES postal_code_areas(postal_code_id) ON DELETE SET NULL
);

CREATE INDEX idx_street_locality ON streets(locality_id);
CREATE INDEX idx_street_postal ON streets(postal_code_id);
CREATE INDEX idx_street_name ON streets(street_name);
CREATE INDEX idx_street_name_normalized ON streets(street_name_normalized);
CREATE INDEX idx_street_name_trgm ON streets USING gin(street_name_normalized gin_trgm_ops);
CREATE INDEX idx_street_composite ON streets(locality_id, street_name_normalized);

COMMENT ON TABLE streets IS 'Street and road names with normalization for fuzzy matching';
COMMENT ON COLUMN streets.street_name_normalized IS 'Uppercase, trimmed version for case-insensitive searching';

-- =====================================================================
-- addresses
-- =====================================================================
CREATE TABLE addresses (
    address_id BIGSERIAL PRIMARY KEY,
    street_id BIGINT NOT NULL,
    locality_id BIGINT NOT NULL,
    division_id BIGINT NOT NULL,
    postal_code_id BIGINT NOT NULL,
    country_id BIGINT NOT NULL,

    street_number VARCHAR(10) NOT NULL,
    unit_number VARCHAR(20),
    unit_type unit_type,

    formatted_address TEXT NOT NULL,
    formatted_address_short TEXT,

    latitude DECIMAL(10, 7),
    longitude DECIMAL(11, 7),
    location GEOGRAPHY(POINT, 4326),

    delivery_point_barcode VARCHAR(50),

    is_verified BOOLEAN NOT NULL DEFAULT false,
    verification_date TIMESTAMPTZ ,
    verification_source validation_source,

    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP ,
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP ,

    CONSTRAINT fk_address_street FOREIGN KEY (street_id)
        REFERENCES streets(street_id) ON DELETE RESTRICT,
    CONSTRAINT fk_address_locality FOREIGN KEY (locality_id)
        REFERENCES localities(locality_id) ON DELETE RESTRICT,
    CONSTRAINT fk_address_division FOREIGN KEY (division_id)
        REFERENCES administrative_divisions(division_id) ON DELETE RESTRICT,
    CONSTRAINT fk_address_postal FOREIGN KEY (postal_code_id)
        REFERENCES postal_code_areas(postal_code_id) ON DELETE RESTRICT,
    CONSTRAINT fk_address_country FOREIGN KEY (country_id)
        REFERENCES countries(country_id) ON DELETE RESTRICT,
    CONSTRAINT chk_unit_type_requires_number CHECK (
        (unit_type IS NULL AND unit_number IS NULL) OR
        (unit_type IS NOT NULL AND unit_number IS NOT NULL)
    )
);

CREATE INDEX idx_address_street ON addresses(street_id);
CREATE INDEX idx_address_locality ON addresses(locality_id);
CREATE INDEX idx_address_division ON addresses(division_id);
CREATE INDEX idx_address_postal ON addresses(postal_code_id);
CREATE INDEX idx_address_country ON addresses(country_id);
CREATE INDEX idx_address_composite ON addresses(street_id, street_number, unit_number);
CREATE INDEX idx_address_location ON addresses USING gist(location);
CREATE INDEX idx_address_verified ON addresses(is_verified) WHERE is_verified = false;
CREATE INDEX idx_address_formatted ON addresses USING gin(to_tsvector('english', formatted_address));

COMMENT ON TABLE addresses IS 'Complete address records with geocoding and verification status';
COMMENT ON COLUMN addresses.formatted_address IS 'Auto-generated full address for display and search';

-- =====================================================================
-- address_aliases
-- =====================================================================
CREATE TABLE address_aliases (
    alias_id BIGSERIAL PRIMARY KEY,
    address_id BIGINT NOT NULL,
    alias_type alias_type NOT NULL,
    alias_value TEXT NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP ,
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP ,

    CONSTRAINT fk_alias_address FOREIGN KEY (address_id)
        REFERENCES addresses(address_id) ON DELETE CASCADE
);

CREATE INDEX idx_alias_address ON address_aliases(address_id);
CREATE INDEX idx_alias_type ON address_aliases(alias_type);
CREATE INDEX idx_alias_value ON address_aliases(alias_value);

COMMENT ON TABLE address_aliases IS 'Alternative address formats: RR, PO Box, historical addresses';

-- =====================================================================
-- address_validation_history
-- =====================================================================
CREATE TABLE address_validation_history (
    validation_id BIGSERIAL PRIMARY KEY,
    address_id BIGINT NOT NULL,
    validation_source validation_source NOT NULL,
    validation_status validation_status NOT NULL,
    validation_date TIMESTAMPTZ TZ  NOT NULL DEFAULT CURRENT_TIMESTAMP ,
    confidence_score DECIMAL(5, 2),
    previous_values JSONB,
    validation_metadata JSONB,
    validated_by VARCHAR(100),

    CONSTRAINT fk_validation_address FOREIGN KEY (address_id)
        REFERENCES addresses(address_id) ON DELETE CASCADE,
    CONSTRAINT chk_confidence_range CHECK (confidence_score BETWEEN 0 AND 100)
);

CREATE INDEX idx_validation_address ON address_validation_history(address_id);
CREATE INDEX idx_validation_date ON address_validation_history(validation_date DESC);
CREATE INDEX idx_validation_status ON address_validation_history(validation_status);
CREATE INDEX idx_validation_source ON address_validation_history(validation_source);
CREATE INDEX idx_validation_composite ON address_validation_history(address_id, validation_date DESC);

COMMENT ON TABLE address_validation_history IS 'Audit trail for all address validation and geocoding updates';
