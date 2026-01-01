-- Enable PostGIS for spatial data types and functions
CREATE EXTENSION IF NOT EXISTS postgis;

-- Enable trigram similarity for fuzzy string matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Enable UUID generation if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
