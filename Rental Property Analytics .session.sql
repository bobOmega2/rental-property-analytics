-- Prevent duplicate tenant contact info
ALTER TABLE tenants ADD CONSTRAINT uq_tenant_email UNIQUE (email);
ALTER TABLE tenants ADD CONSTRAINT uq_tenant_phone UNIQUE (phone);

-- Prevent duplicate property addresses
ALTER TABLE properties ADD CONSTRAINT uq_property_address UNIQUE (address);

-- Security deposit can't be negative 
ALTER TABLE leases ADD CONSTRAINT chk_deposit_positive 
    CHECK (security_deposit IS NULL OR security_deposit >= 0);

-- Square footage must be positive 
ALTER TABLE units ADD CONSTRAINT chk_sqft_positive 
    CHECK (square_feet IS NULL OR square_feet > 0);

-- Canadian postal code format: A1A 1A1
ALTER TABLE properties ADD CONSTRAINT chk_postal_code_format
    CHECK (postal_code ~ '^[A-Z][0-9][A-Z] [0-9][A-Z][0-9]$');
