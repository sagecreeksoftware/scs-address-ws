DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'division_type') THEN
        CREATE TYPE division_type AS ENUM (
            'province','state','territory','county','region','district','municipality'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'locality_type') THEN
        CREATE TYPE locality_type AS ENUM (
            'city','town','village','hamlet','borough','settlement'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'unit_type') THEN
        CREATE TYPE unit_type AS ENUM (
            'apartment','suite','unit','floor','room','building','penthouse','basement'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'alias_type') THEN
        CREATE TYPE alias_type AS ENUM (
            'rural_route','po_box','historical','alternative','general_delivery'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'validation_source') THEN
        CREATE TYPE validation_source AS ENUM (
            'canada_post','usps','google_maps','here_maps','manual','import','user_input'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'validation_status') THEN
        CREATE TYPE validation_status AS ENUM (
            'valid','invalid','partial','unverifiable','pending'
        );
    END IF;
END
$$;
