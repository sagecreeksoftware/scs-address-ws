-- =====================================================================
-- Auto-update updated_at
-- =====================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_countries_updated_at
    BEFORE UPDATE ON countries
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_admin_divisions_updated_at
    BEFORE UPDATE ON administrative_divisions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_postal_codes_updated_at
    BEFORE UPDATE ON postal_code_areas
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_localities_updated_at
    BEFORE UPDATE ON localities
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_streets_updated_at
    BEFORE UPDATE ON streets
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_addresses_updated_at
    BEFORE UPDATE ON addresses
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_aliases_updated_at
    BEFORE UPDATE ON address_aliases
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =====================================================================
-- Location from lat/long (generic for tables with latitude/longitude/location)
-- =====================================================================
CREATE OR REPLACE FUNCTION update_location_from_coordinates()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL THEN
        NEW.location := ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_addresses_location
    BEFORE INSERT OR UPDATE ON addresses
    FOR EACH ROW
    WHEN (NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL)
    EXECUTE FUNCTION update_location_from_coordinates();

CREATE TRIGGER trg_localities_location
    BEFORE INSERT OR UPDATE ON localities
    FOR EACH ROW
    WHEN (NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL)
    EXECUTE FUNCTION update_location_from_coordinates();

CREATE TRIGGER trg_postal_location
    BEFORE INSERT OR UPDATE ON postal_code_areas
    FOR EACH ROW
    WHEN (NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL)
    EXECUTE FUNCTION update_location_from_coordinates();

-- =====================================================================
-- Normalize street names
-- =====================================================================
CREATE OR REPLACE FUNCTION normalize_street_name()
RETURNS TRIGGER AS $$
BEGIN
    NEW.street_name_normalized := UPPER(TRIM(NEW.street_name));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_normalize_street_name
    BEFORE INSERT OR UPDATE ON streets
    FOR EACH ROW
    EXECUTE FUNCTION normalize_street_name();

-- =====================================================================
-- Normalize postal codes
-- =====================================================================
CREATE OR REPLACE FUNCTION normalize_postal_code()
RETURNS TRIGGER AS $$
BEGIN
    -- remove all non-alphanumerics and uppercase (handles spaces, hyphens, etc.)
    NEW.postal_code_normalized := UPPER(regexp_replace(NEW.postal_code, '[^A-Z0-9]', '', 'g'));

    IF LENGTH(NEW.postal_code_normalized) >= 3 THEN
        NEW.postal_code_prefix := LEFT(NEW.postal_code_normalized, 3);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_normalize_postal_code
    BEFORE INSERT OR UPDATE ON postal_code_areas
    FOR EACH ROW
    EXECUTE FUNCTION normalize_postal_code();

-- =====================================================================
-- Generate formatted address
-- =====================================================================
CREATE OR REPLACE FUNCTION generate_formatted_address()
RETURNS TRIGGER AS $$
DECLARE
    v_street_name TEXT;
    v_street_type TEXT;
    v_street_direction TEXT;
    v_locality_name TEXT;
    v_division_code TEXT;
    v_postal_code TEXT;
    v_country_code TEXT;
BEGIN
    SELECT
        s.street_name,
        s.street_type,
        s.street_direction,
        l.locality_name,
        ad.division_code,
        pc.postal_code,
        c.iso_alpha2_code
    INTO
        v_street_name,
        v_street_type,
        v_street_direction,
        v_locality_name,
        v_division_code,
        v_postal_code,
        v_country_code
    FROM streets s
    JOIN localities l ON l.locality_id = s.locality_id
    JOIN administrative_divisions ad ON ad.division_id = NEW.division_id
    JOIN postal_code_areas pc ON pc.postal_code_id = NEW.postal_code_id
    JOIN countries c ON c.country_id = NEW.country_id
    WHERE s.street_id = NEW.street_id;

    NEW.formatted_address := CONCAT_WS(' ',
        NEW.street_number,
        v_street_name,
        v_street_type,
        v_street_direction,
        CASE WHEN NEW.unit_number IS NOT NULL
            THEN CONCAT(INITCAP(NEW.unit_type::TEXT), ' ', NEW.unit_number)
            ELSE NULL
        END
    ) || E'\n' ||
    v_locality_name || ' ' || v_division_code || '  ' || v_postal_code || E'\n' ||
    v_country_code;

    NEW.formatted_address_short := CONCAT_WS(' ',
        NEW.street_number,
        v_street_name,
        v_street_type,
        v_street_direction,
        CASE WHEN NEW.unit_number IS NOT NULL
            THEN CONCAT(INITCAP(NEW.unit_type::TEXT), ' ', NEW.unit_number)
            ELSE NULL
        END
    ) || E'\n' ||
    v_locality_name || ' ' || v_division_code || '  ' || v_postal_code;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_generate_formatted_address
    BEFORE INSERT OR UPDATE ON addresses
    FOR EACH ROW
    EXECUTE FUNCTION generate_formatted_address();
