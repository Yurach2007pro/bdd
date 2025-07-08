-- Создание ролей и назначение прав
CREATE ROLE InventoryManager;
GRANT SELECT, INSERT, UPDATE ON Products TO InventoryManager;
GRANT SELECT, INSERT, UPDATE ON Batches TO InventoryManager;
GRANT SELECT, INSERT, UPDATE ON ProductPlacements TO InventoryManager;
GRANT EXECUTE ON sp_RegisterProductionBatch TO InventoryManager;
GRANT EXECUTE ON sp_MoveBetweenWarehouses TO InventoryManager;

CREATE ROLE WarehouseWorker;
GRANT SELECT ON Products TO WarehouseWorker;
GRANT SELECT, UPDATE ON Batches TO WarehouseWorker;
GRANT SELECT, INSERT, UPDATE ON ProductPlacements TO WarehouseWorker;
GRANT SELECT, INSERT ON ProductTransactions TO WarehouseWorker;
GRANT EXECUTE ON sp_MoveBetweenWarehouses TO WarehouseWorker;

CREATE ROLE SalesManager;
GRANT SELECT ON Products TO SalesManager;
GRANT SELECT ON Batches TO SalesManager;
GRANT EXECUTE ON sp_RegisterShipment TO SalesManager;
GRANT SELECT, INSERT ON Shipments TO SalesManager;

-- Row-Level Security для ограничения доступа по складам
CREATE SCHEMA Security;
GO

CREATE FUNCTION Security.fn_WarehouseAccessPredicate(@WarehouseID INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS AccessResult
FROM dbo.EmployeeWarehouses ew
WHERE ew.EmployeeID = CAST(SESSION_CONTEXT(N'EmployeeID') AS INT)
AND ew.WarehouseID = @WarehouseID;
GO

CREATE SECURITY POLICY Security.WarehouseAccessPolicy
ADD FILTER PREDICATE Security.fn_WarehouseAccessPredicate(WarehouseID)
ON dbo.Warehouses,
ADD BLOCK PREDICATE Security.fn_WarehouseAccessPredicate(WarehouseID)
ON dbo.Warehouses;
GO