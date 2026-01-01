-- =====================================================================
-- countries
-- =====================================================================
CREATE TABLE countries (
    country_id BIGSERIAL PRIMARY KEY,
    iso_alpha2_code CHAR(2) NOT NULL UNIQUE,
    iso_alpha3_code CHAR(3) NOT NULL UNIQUE,
    country_name VARCHAR(100) NOT NULL,
    country_name_native VARCHAR(100),
    phone_prefix VARCHAR(10),
    postal_code_format VARCHAR(50),
    postal_code_example VARCHAR(20),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_iso_alpha2_upper CHECK (iso_alpha2_code = UPPER(iso_alpha2_code)),
    CONSTRAINT chk_iso_alpha3_upper CHECK (iso_alpha3_code = UPPER(iso_alpha3_code))
);

CREATE INDEX idx_countries_active ON countries(is_active) WHERE is_active = true;

COMMENT ON TABLE countries IS 'Master reference table for all countries with ISO codes and postal format rules';
COMMENT ON COLUMN countries.postal_code_format IS 'Regex pattern for validating postal codes, e.g., ^[A-Z]\d[A-Z]\d[A-Z]\d$ for Canada';

-- =====================================================================
-- administrative_divisions
-- =====================================================================
CREATE TABLE administrative_divisions (
    division_id BIGSERIAL PRIMARY KEY,
    country_id BIGINT NOT NULL,
    parent_division_id BIGINT,
    division_code VARCHAR(10) NOT NULL,
    division_name VARCHAR(100) NOT NULL,
    division_name_native VARCHAR(100),
    division_type division_type NOT NULL,
    abbreviation VARCHAR(10),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_admin_country FOREIGN KEY (country_id)
        REFERENCES countries(country_id) ON DELETE RESTRICT,
    CONSTRAINT fk_admin_parent FOREIGN KEY (parent_division_id)
        REFERENCES administrative_divisions(division_id) ON DELETE RESTRICT,
    CONSTRAINT uq_division_code_country UNIQUE (country_id, division_code),
    CONSTRAINT chk_no_self_reference CHECK (division_id != parent_division_id)
);

CREATE INDEX idx_admin_country ON administrative_divisions(country_id);
CREATE INDEX idx_admin_parent ON administrative_divisions(parent_division_id);
CREATE INDEX idx_admin_code ON administrative_divisions(division_code);
CREATE INDEX idx_admin_type ON administrative_divisions(division_type);
CREATE INDEX idx_admin_name_trgm ON administrative_divisions USING gin(division_name gin_trgm_ops);

COMMENT ON TABLE administrative_divisions IS 'Hierarchical storage of provinces, states, counties, and municipalities';
COMMENT ON COLUMN administrative_divisions.parent_division_id IS 'Self-referencing FK for hierarchy, e.g., county -> province';
