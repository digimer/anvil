-- This is the core database schema for ScanCore. 
-- It builds on AN::Tools.sql.

-- NOTE: network_interfaces, network_bonds and network_bridges are all used by scan-network (which doesn't 
--       exist yet).

-- This stores information about network interfaces on hosts. It is mainly used to match a MAC address to a
-- host. Given that it is possible that network devices can move, the linkage to the host_uuid can change.
CREATE TABLE network_interfaces (
	network_interface_uuid			uuid				not null	primary key,
	network_interface_host_uuid		uuid				not null,
	network_interface_mac_address		text,								-- This is allowed to be NULL to support bonds and bridges
	network_interface_current_name		text				not null,			-- This is the current name of the interface. 
	network_interface_requested_name	text,								-- This is the name of the interface that the user requested. This will differ from the current name pending a commit request by the user.
	network_interface_speed			number				not null,			-- This is the speed, in bits-per-second, of the interface.
	network_interface_mtu			number,								-- This is the MTU (Maximum Transmitable Size), in bytes, for this interface.
	network_interface_link_state		text				not null,			-- This is 'up', 'down' or 'unknown' 
	network_interface_duplex		text				not null,			-- This is 'full', 'half' or 'unknown' 
	network_interface_medium		text				not null,			-- This is 'tp' (twisted pair), 'fiber' or whatever they invent in the future.
	network_interface_bond_uuid		uuid,								-- If this iface is in a bond, this will contain the 'bonds -> bond_uuid' that it is slaved to.
	network_interface_bridge_uuid		uuid,								-- If this iface is attached to a bridge, this will contain the 'bridgess -> bridge_uuid' that it is connected to.
	modified_date				timestamp with time zone	not null
);
ALTER TABLE network_interface OWNER TO #!variable!user!#;

CREATE TABLE history.network_interface (
	history_id				bigserial,
	network_interface_uuid			uuid				not null,
	network_interface_host_uuid		uuid,
	network_interface_mac_address		text,
	network_interface_current_name		text,
	network_interface_requested_name	text,
	network_interface_speed			number,
	network_interface_mtu			number,
	network_interface_link_state		text,
	network_interface_duplex		text,
	network_interface_medium		text,
	network_interface_bond_uuid		uuid,
	network_interface_bridge_uuid		uuid,
	modified_date				timestamp with time zone	not null
);
ALTER TABLE history.network_interface OWNER TO #!variable!user!#;

CREATE FUNCTION history_network_interface() RETURNS trigger
AS $$
DECLARE
	history_network_interface RECORD;
BEGIN
	SELECT INTO history_network_interface * FROM network_interface WHERE host_uuid = new.host_uuid;
	INSERT INTO history.network_interface
		(network_interface_uuid,
		 network_interface_host_uuid, 
		 network_interface_mac_address, 
		 network_interface_current_name,
		 network_interface_requested_name,
		 network_interface_speed, 
		 network_interface_mtu, 
		 network_interface_link_state, 
		 network_interface_duplex, 
		 network_interface_medium, 
		 network_interface_bond_uuid, 
		 network_interface_bridge_uuid, 
		 modified_date)
	VALUES
		(history_network_interface.network_interface_uuid,
		 history_network_interface.network_interface_host_uuid, 
		 history_network_interface.network_interface_mac_address, 
		 history_network_interface.network_interface_current_name,
		 history_network_interface.network_interface_requested_name,
		 history_network_interface.network_interface_speed, 
		 history_network_interface.network_interface_mtu, 
		 history_network_interface.network_interface_link_state, 
		 history_network_interface.network_interface_duplex, 
		 history_network_interface.network_interface_medium, 
		 history_network_interface.network_interface_bond_uuid, 
		 history_network_interface.network_interface_bridge_uuid, 
		 history_network_interface.modified_date);
	RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_network_interface() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_network_interface
	AFTER INSERT OR UPDATE ON network_interface
	FOR EACH ROW EXECUTE PROCEDURE history_network_interface();


-- This stores information about network bonds (mode=1) on a hosts.
CREATE TABLE bonds (
	bond_uuid			uuid				primary key,
	bond_host_uuid			uuid				not null,
	bond_name			text				not null,
	bond_mode			numeric				not null,	-- This is the numerical bond type (will translate to the user's language in ScanCore)
	bond_mtu			numeric,
	bond_primary_slave		text,
	bond_primary_reselect		text,
	bond_active_slave		text,
	bond_mii_status			text,
	bond_mii_polling_interval	numeric,
	bond_up_delay			numeric,
	bond_down_delay			numeric,
	modified_date			timestamp with time zone	not null,
	
	FOREIGN KEY(bond_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE bonds OWNER TO #!variable!user!#;

CREATE TABLE history.bonds (
	history_id			bigserial,
	bond_uuid			uuid,
	bond_host_uuid			uuid,
	bond_name			text,
	bond_mode			numeric,
	bond_mtu			numeric,
	bond_primary_slave		text,
	bond_primary_reselect		text,
	bond_active_slave		text,
	bond_mii_status			text,
	bond_mii_polling_interval	numeric,
	bond_up_delay			numeric,
	bond_down_delay			numeric,
	modified_date			timestamp with time zone	not null
);
ALTER TABLE history.bonds OWNER TO #!variable!user!#;

CREATE FUNCTION history_bonds() RETURNS trigger
AS $$
DECLARE
	history_bonds RECORD;
BEGIN
	SELECT INTO history_bonds * FROM bonds WHERE bond_uuid=new.bond_uuid;
	INSERT INTO history.bonds
		(bond_uuid,
		 bond_host_uuid,
		 bond_name, 
		 bond_mode, 
		 bond_mtu, 
		 bond_primary_slave, 
		 bond_primary_reselect, 
		 bond_active_slave, 
		 bond_mii_status, 
		 bond_mii_polling_interval, 
		 bond_up_delay, 
		 bond_down_delay, 
		 modified_date)
	VALUES
		(history_bond.bond_uuid,
		 history_bond.bond_host_uuid,
		 history_bond.bond_name, 
		 history_bond.bond_mode, 
		 history_bond.bond_mtu, 
		 history_bond.bond_primary_slave, 
		 history_bond.bond_primary_reselect, 
		 history_bond.bond_active_slave, 
		 history_bond.bond_mii_status, 
		 history_bond.bond_mii_polling_interval, 
		 history_bond.bond_up_delay, 
		 history_bond.bond_down_delay, 
		 history_bond.modified_date);
	RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_bonds() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_bond
	AFTER INSERT OR UPDATE ON bonds
	FOR EACH ROW EXECUTE PROCEDURE history_bond();


-- This stores information about network bridges. 
CREATE TABLE bridges (
	bridge_uuid			uuid				primary key,
	bridge_host_uuid		uuid				not null,
	bridge_name			text				not null,
	bridge_id			text,
	bridge_stp_enabled		text,
	modified_date			timestamp with time zone	not null,
	
	FOREIGN KEY(bridge_host_uuid) REFERENCES hosts(host_uuid)
);
ALTER TABLE bridges OWNER TO #!variable!user!#;

CREATE TABLE history.bridges (
	history_id			bigserial,
	bridge_uuid			uuid,
	bridge_host_uuid		uuid,
	bridge_name			text,
	bridge_id			text,
	bridge_stp_enabled		text,
	modified_date			timestamp with time zone	not null
);
ALTER TABLE history.bridges OWNER TO #!variable!user!#;

CREATE FUNCTION history_bridges() RETURNS trigger
AS $$
DECLARE
	history_bridges RECORD;
BEGIN
	SELECT INTO history_bridges * FROM bridges WHERE bridge_uuid=new.bridge_uuid;
	INSERT INTO history.bridges
		(bridge_uuid,
		 bridge_host_uuid,
		 bridge_name, 
		 bridge_name,
		 bridge_id,
		 bridge_stp_enabled,
		 modified_date)
	VALUES
		(history_bridge.bridge_uuid,
		 history_bridge.bridge_host_uuid,
		 history_bridge.bridge_name, 
		 history_bridge.bridge_name,
		 history_bridge.bridge_id,
		 history_bridge.bridge_stp_enabled,
		 history_bridge.modified_date);
	RETURN NULL;
END;
$$
LANGUAGE plpgsql;
ALTER FUNCTION history_bridges() OWNER TO #!variable!user!#;

CREATE TRIGGER trigger_bridge
	AFTER INSERT OR UPDATE ON bridges
	FOR EACH ROW EXECUTE PROCEDURE history_bridge();

