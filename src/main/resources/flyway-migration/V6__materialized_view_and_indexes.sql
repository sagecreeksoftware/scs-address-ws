CREATE MATERIALIZED VIEW address_components_cache AS
SELECT
    a.address_id,
    a.street_number,
    a.unit_number,
    a.unit_type,
    a.formatted_address,
    a.formatted_address_short,
    a.latitude,
    a.longitude,
    a.is_verified,
    a.verification_date,

    s.street_name,
    s.street_type,
    s.street_direction,

    l.locality_name,
    l.locality_type,

    ad.division_name,
    ad.division_code,
    ad.division_type,

    pc.postal_code,
    pc.postal_code_prefix,
    pc.timezone,

    c.country_name,
    c.iso_alpha2_code,
    c.iso_alpha3_code,

    a.created_at,
    a.updated_at
FROM addresses a
JOIN streets s ON s.street_id = a.street_id
JOIN localities l ON l.locality_id = a.locality_id
JOIN administrative_divisions ad ON ad.division_id = a.division_id
JOIN postal_code_areas pc ON pc.postal_code_id = a.postal_code_id
JOIN countries c ON c.country_id = a.country_id
WHERE a.is_active = true;

CREATE UNIQUE INDEX idx_mv_address_cache_id ON address_components_cache(address_id);
CREATE INDEX idx_mv_address_cache_postal ON address_components_cache(postal_code);
CREATE INDEX idx_mv_address_cache_locality ON address_components_cache(locality_name);
CREATE INDEX idx_mv_address_cache_division ON address_components_cache(division_code);
CREATE INDEX idx_mv_address_cache_country ON address_components_cache(iso_alpha2_code);
CREATE INDEX idx_mv_address_cache_verified ON address_components_cache(is_verified);

COMMENT ON MATERIALIZED VIEW address_components_cache IS 'Denormalized view for fast full-address queries without joins';
