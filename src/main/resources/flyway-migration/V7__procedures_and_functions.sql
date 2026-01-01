-- Refresh cache (non-concurrent to be migration-safe)
CREATE OR REPLACE PROCEDURE refresh_address_cache()
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW address_components_cache;
    RAISE NOTICE 'Address components cache refreshed at %', CURRENT_TIMESTAMP;
END;
$$;

COMMENT ON PROCEDURE refresh_address_cache IS 'Refreshes the denormalized address cache materialized view';

-- Validate address + write history
CREATE OR REPLACE FUNCTION validate_address(
    p_address_id BIGINT,
    p_validation_source validation_source,
    p_validation_status validation_status,
    p_confidence_score DECIMAL DEFAULT NULL,
    p_validated_by VARCHAR DEFAULT 'SYSTEM',
    p_metadata JSONB DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_verified BOOLEAN;
    v_previous_values JSONB;
BEGIN
    SELECT is_verified INTO v_current_verified
    FROM addresses
    WHERE address_id = p_address_id;

    IF v_current_verified IS NULL THEN
        RAISE EXCEPTION 'Address ID % not found', p_address_id;
    END IF;

    v_previous_values := jsonb_build_object('was_verified', v_current_verified);

    UPDATE addresses
    SET
        is_verified = (p_validation_status = 'valid'),
        verification_date = CURRENT_TIMESTAMP,
        verification_source = p_validation_source
    WHERE address_id = p_address_id;

    INSERT INTO address_validation_history (
        address_id,
        validation_source,
        validation_status,
        confidence_score,
        previous_values,
        validation_metadata,
        validated_by
    ) VALUES (
        p_address_id,
        p_validation_source,
        p_validation_status,
        p_confidence_score,
        v_previous_values,
        p_metadata,
        p_validated_by
    );

    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error validating address %: %', p_address_id, SQLERRM;
        RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION validate_address IS 'Validates an address and records the validation in history';

-- Find addresses within radius
CREATE OR REPLACE FUNCTION find_addresses_within_radius(
    p_latitude DECIMAL,
    p_longitude DECIMAL,
    p_radius_meters INTEGER,
    p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
    address_id BIGINT,
    formatted_address TEXT,
    distance_meters DOUBLE PRECISION,
    latitude DECIMAL,
    longitude DECIMAL
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.address_id,
        a.formatted_address,
        ST_Distance(
            a.location,
            ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography
        ) AS distance_meters,
        a.latitude,
        a.longitude
    FROM addresses a
    WHERE
        a.location IS NOT NULL
        AND ST_DWithin(
            a.location,
            ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography,
            p_radius_meters
        )
    ORDER BY distance_meters ASC
    LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION find_addresses_within_radius IS 'Finds addresses within specified radius using PostGIS';

-- Administrative hierarchy
CREATE OR REPLACE FUNCTION get_administrative_hierarchy(p_division_id BIGINT)
RETURNS TABLE (
    level INTEGER,
    division_id BIGINT,
    division_name VARCHAR,
    division_type division_type,
    division_code VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE hierarchy AS (
        SELECT
            1 AS level,
            ad.division_id,
            ad.division_name,
            ad.division_type,
            ad.division_code,
            ad.parent_division_id
        FROM administrative_divisions ad
        WHERE ad.division_id = p_division_id
        UNION ALL
        SELECT
            h.level + 1,
            ad.division_id,
            ad.division_name,
            ad.division_type,
            ad.division_code,
            ad.parent_division_id
        FROM administrative_divisions ad
        JOIN hierarchy h ON ad.division_id = h.parent_division_id
    )
    SELECT
        h.level, h.division_id, h.division_name, h.division_type, h.division_code
    FROM hierarchy h
    ORDER BY h.level DESC;
END;
$$;

COMMENT ON FUNCTION get_administrative_hierarchy IS 'Returns complete administrative hierarchy for a division';

-- Fuzzy street search
CREATE OR REPLACE FUNCTION fuzzy_street_search(
    p_street_name VARCHAR,
    p_locality_id BIGINT DEFAULT NULL,
    p_similarity_threshold REAL DEFAULT 0.3,
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    street_id BIGINT,
    street_name VARCHAR,
    street_type VARCHAR,
    locality_name VARCHAR,
    similarity_score REAL
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.street_id,
        s.street_name,
        s.street_type,
        l.locality_name,
        similarity(s.street_name_normalized, UPPER(p_street_name)) AS similarity_score
    FROM streets s
    JOIN localities l ON l.locality_id = s.locality_id
    WHERE
        (p_locality_id IS NULL OR s.locality_id = p_locality_id)
        AND similarity(s.street_name_normalized, UPPER(p_street_name)) > p_similarity_threshold
    ORDER BY similarity_score DESC
    LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION fuzzy_street_search IS 'Fuzzy matching on street names using trigram similarity';

-- Validate postal format
CREATE OR REPLACE FUNCTION validate_postal_code_format(
    p_postal_code VARCHAR,
    p_country_code CHAR(2)
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_format_pattern VARCHAR(50);
    v_normalized_code VARCHAR(10);
BEGIN
    SELECT postal_code_format INTO v_format_pattern
    FROM countries
    WHERE iso_alpha2_code = p_country_code;

    IF v_format_pattern IS NULL THEN
        RAISE NOTICE 'No format pattern found for country %', p_country_code;
        RETURN NULL;
    END IF;

    v_normalized_code := UPPER(regexp_replace(p_postal_code, '[^A-Z0-9]', '', 'g'));
    RETURN v_normalized_code ~ v_format_pattern;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error validating postal code: %', SQLERRM;
        RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION validate_postal_code_format IS 'Validates postal code against country-specific regex pattern';

-- Bulk geocode placeholder
CREATE OR REPLACE PROCEDURE bulk_geocode_addresses(
    p_batch_size INTEGER DEFAULT 100,
    p_source validation_source DEFAULT 'manual'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_processed_count INTEGER := 0;
    v_address_record RECORD;
BEGIN
    FOR v_address_record IN
        SELECT address_id
        FROM addresses
        WHERE (latitude IS NULL OR longitude IS NULL)
          AND is_verified = false
        LIMIT p_batch_size
    LOOP
        PERFORM validate_address(
            v_address_record.address_id,
            p_source,
            'pending',
            NULL,
            'BULK_GEOCODE_PROCESS'
        );
        v_processed_count := v_processed_count + 1;
    END LOOP;

    RAISE NOTICE 'Processed % addresses for geocoding', v_processed_count;
END;
$$;

COMMENT ON PROCEDURE bulk_geocode_addresses IS 'Batch marks unverified addresses as pending geocoding';

-- Duplicate finder
CREATE OR REPLACE FUNCTION find_duplicate_addresses(p_limit INTEGER DEFAULT 100)
RETURNS TABLE (
    street_id BIGINT,
    street_number VARCHAR,
    unit_number VARCHAR,
    duplicate_count BIGINT,
    address_ids BIGINT[]
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.street_id,
        a.street_number,
        a.unit_number,
        COUNT(*) AS duplicate_count,
        array_agg(a.address_id ORDER BY a.address_id) AS address_ids
    FROM addresses a
    WHERE a.is_active = true
    GROUP BY a.street_id, a.street_number, a.unit_number
    HAVING COUNT(*) > 1
    ORDER BY COUNT(*) DESC
    LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION find_duplicate_addresses IS 'Identifies potential duplicate addresses';

-- Division stats
CREATE OR REPLACE FUNCTION get_address_statistics_by_division(p_division_id BIGINT)
RETURNS TABLE (
    total_addresses BIGINT,
    verified_addresses BIGINT,
    unverified_addresses BIGINT,
    geocoded_addresses BIGINT,
    verification_rate DECIMAL,
    geocoding_rate DECIMAL
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) AS total_addresses,
        COUNT(*) FILTER (WHERE is_verified = true) AS verified_addresses,
        COUNT(*) FILTER (WHERE is_verified = false) AS unverified_addresses,
        COUNT(*) FILTER (WHERE latitude IS NOT NULL AND longitude IS NOT NULL) AS geocoded_addresses,
        ROUND(
            (COUNT(*) FILTER (WHERE is_verified = true)::DECIMAL / NULLIF(COUNT(*), 0)) * 100,
            2
        ) AS verification_rate,
        ROUND(
            (COUNT(*) FILTER (WHERE latitude IS NOT NULL AND longitude IS NOT NULL)::DECIMAL / NULLIF(COUNT(*), 0)) * 100,
            2
        ) AS geocoding_rate
    FROM addresses
    WHERE division_id = p_division_id
      AND is_active = true;
END;
$$;

COMMENT ON FUNCTION get_address_statistics_by_division IS 'Returns address quality metrics for a division';

-- Search addresses (full text + optional spatial)
CREATE OR REPLACE FUNCTION search_addresses(
    p_search_text VARCHAR DEFAULT NULL,
    p_latitude DECIMAL DEFAULT NULL,
    p_longitude DECIMAL DEFAULT NULL,
    p_radius_meters INTEGER DEFAULT 5000,
    p_country_code CHAR(2) DEFAULT NULL,
    p_division_code VARCHAR DEFAULT NULL,
    p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
    address_id BIGINT,
    formatted_address TEXT,
    street_name VARCHAR,
    locality_name VARCHAR,
    division_code VARCHAR,
    postal_code VARCHAR,
    distance_meters DOUBLE PRECISION,
    relevance_rank REAL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_search_point GEOGRAPHY;
BEGIN
    IF p_latitude IS NOT NULL AND p_longitude IS NOT NULL THEN
        v_search_point := ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography;
    END IF;

    RETURN QUERY
    SELECT
        acc.address_id,
        acc.formatted_address,
        acc.street_name,
        acc.locality_name,
        acc.division_code,
        acc.postal_code,
        CASE
            WHEN v_search_point IS NOT NULL AND a.location IS NOT NULL THEN
                ST_Distance(a.location, v_search_point)
            ELSE NULL
        END AS distance_meters,
        CASE
            WHEN p_search_text IS NOT NULL THEN
                ts_rank(
                    to_tsvector('english', acc.formatted_address),
                    plainto_tsquery('english', p_search_text)
                )
            ELSE 0
        END AS relevance_rank
    FROM address_components_cache acc
    JOIN addresses a ON a.address_id = acc.address_id
    WHERE
        acc.is_verified = true
        AND (p_country_code IS NULL OR acc.iso_alpha2_code = p_country_code)
        AND (p_division_code IS NULL OR acc.division_code = p_division_code)
        AND (
            p_search_text IS NULL
            OR to_tsvector('english', acc.formatted_address) @@ plainto_tsquery('english', p_search_text)
        )
        AND (
            v_search_point IS NULL
            OR (a.location IS NOT NULL AND ST_DWithin(a.location, v_search_point, p_radius_meters))
        )
    ORDER BY
        CASE WHEN p_search_text IS NOT NULL THEN relevance_rank ELSE 0 END DESC,
        CASE WHEN v_search_point IS NOT NULL THEN distance_meters ELSE 0 END ASC
    LIMIT p_limit;
END;
$$;

COMMENT ON FUNCTION search_addresses IS 'Comprehensive address search combining full-text and spatial queries';
