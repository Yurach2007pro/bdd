-- 1. Процедура регистрации новой партии
CREATE PROCEDURE sp_RegisterProductionBatch
    @ProductID INT,
    @Quantity INT,
    @ProductionLineID INT = NULL,
    @ExpirationDate DATETIME2 = NULL,
    @ResponsibleEmployeeID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @BatchNumber VARCHAR(20) = FORMAT(GETDATE(), 'yyyy-MM-dd') + '-' + 
                                      RIGHT('000' + CAST(ABS(CHECKSUM(NEWID())) % 1000 AS VARCHAR(3));
    
    BEGIN TRANSACTION;
    BEGIN TRY
        INSERT INTO Batches (
            ProductID, 
            BatchNumber, 
            ProductionLineID, 
            Quantity, 
            ExpirationDate, 
            StatusID, 
            ResponsibleEmployeeID
        )
        VALUES (
            @ProductID,
            @BatchNumber,
            @ProductionLineID,
            @Quantity,
            @ExpirationDate,
            1, -- Статус "В производстве"
            @ResponsibleEmployeeID
        );
        
        DECLARE @BatchID UNIQUEIDENTIFIER = SCOPE_IDENTITY();
        
        -- Автоматическое размещение в цеховом накопителе
        DECLARE @WorkshopWarehouseID INT = (SELECT TOP 1 WarehouseID FROM Warehouses WHERE Code LIKE 'WS%');
        DECLARE @WorkshopCellID INT = (SELECT TOP 1 CellID FROM StorageCells WHERE WarehouseID = @WorkshopWarehouseID);
        
        INSERT INTO ProductPlacements (BatchID, CellID, Quantity, EmployeeID)
        VALUES (@BatchID, @WorkshopCellID, @Quantity, @ResponsibleEmployeeID);
        
        INSERT INTO ProductTransactions (
            TransactionType,
            BatchID,
            ToCellID,
            Quantity,
            EmployeeID,
            DocumentNumber
        )
        VALUES (
            'Поступление',
            @BatchID,
            @WorkshopCellID,
            @Quantity,
            @ResponsibleEmployeeID,
            'PR-' + @BatchNumber
        );
        
        COMMIT TRANSACTION;
        
        SELECT @BatchID AS NewBatchID, @BatchNumber AS BatchNumber;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 2. Процедура перемещения между складами
CREATE PROCEDURE sp_MoveBetweenWarehouses
    @BatchID UNIQUEIDENTIFIER,
    @FromCellID INT,
    @ToCellID INT,
    @Quantity INT,
    @EmployeeID INT,
    @DocumentNumber VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRANSACTION;
    BEGIN TRY
        -- Проверка наличия достаточного количества
        DECLARE @AvailableQuantity INT = (
            SELECT Quantity FROM ProductPlacements 
            WHERE BatchID = @BatchID AND CellID = @FromCellID
        );
        
        IF @AvailableQuantity < @Quantity
        BEGIN
            RAISERROR('Недостаточно продукции в ячейке-источнике', 16, 1);
            RETURN;
        END;
        
        -- Обновление количества в исходной ячейке
        UPDATE ProductPlacements
        SET Quantity = Quantity - @Quantity
        WHERE BatchID = @BatchID AND CellID = @FromCellID;
        
        -- Добавление или обновление в целевой ячейке
        MERGE ProductPlacements AS target
        USING (SELECT @BatchID, @ToCellID, @Quantity) AS source (BatchID, CellID, Quantity)
        ON target.BatchID = source.BatchID AND target.CellID = source.CellID
        WHEN MATCHED THEN
            UPDATE SET Quantity = target.Quantity + source.Quantity
        WHEN NOT MATCHED THEN
            INSERT (BatchID, CellID, Quantity, PlacementDate, EmployeeID)
            VALUES (source.BatchID, source.CellID, source.Quantity, GETDATE(), @EmployeeID);
        
        -- Регистрация транзакции
        INSERT INTO ProductTransactions (
            TransactionType,
            BatchID,
            FromCellID,
            ToCellID,
            Quantity,
            EmployeeID,
            DocumentNumber
        )
        VALUES (
            'Перемещение',
            @BatchID,
            @FromCellID,
            @ToCellID,
            @Quantity,
            @EmployeeID,
            @DocumentNumber
        );
        
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 3. Процедура отгрузки продукции клиенту
CREATE PROCEDURE sp_RegisterShipment
    @BatchID UNIQUEIDENTIFIER,
    @FromCellID INT,
    @CustomerID INT,
    @Quantity INT,
    @ExpectedDeliveryDate DATETIME2,
    @EmployeeID INT,
    @TransportDetails NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    BEGIN TRANSACTION;
    BEGIN TRY
        -- Проверка наличия
        DECLARE @AvailableQuantity INT = (
            SELECT Quantity FROM ProductPlacements 
            WHERE BatchID = @BatchID AND CellID = @FromCellID
        );
        
        IF @AvailableQuantity < @Quantity
        BEGIN
            RAISERROR('Недостаточно продукции для отгрузки', 16, 1);
            RETURN;
        END;
        
        -- Списание со склада
        UPDATE ProductPlacements
        SET Quantity = Quantity - @Quantity
        WHERE BatchID = @BatchID AND CellID = @FromCellID;
        
        -- Если вся партия отгружена, удаляем запись
        IF @AvailableQuantity - @Quantity = 0
        BEGIN
            DELETE FROM ProductPlacements 
            WHERE BatchID = @BatchID AND CellID = @FromCellID;
        END;
        
        -- Регистрация отгрузки
        INSERT INTO Shipments (
            BatchID,
            FromWarehouseID,
            ToCustomerID,
            ExpectedDeliveryDate,
            Status,
            TransportDetails
        )
        VALUES (
            @BatchID,
            (SELECT WarehouseID FROM StorageCells WHERE CellID = @FromCellID),
            @CustomerID,
            @ExpectedDeliveryDate,
            'Preparing',
            @TransportDetails
        );
        
        -- Регистрация транзакции
        INSERT INTO ProductTransactions (
            TransactionType,
            BatchID,
            FromCellID,
            Quantity,
            EmployeeID,
            DocumentNumber
        )
        VALUES (
            'Отгрузка',
            @BatchID,
            @FromCellID,
            @Quantity,
            @EmployeeID,
            (SELECT 'SH-' + BatchNumber FROM Batches WHERE BatchID = @BatchID)
        );
        
        -- Обновление статуса партии
        UPDATE Batches
        SET StatusID = 5 -- Статус "Отгружено"
        WHERE BatchID = @BatchID;
        
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 4. Триггер для аудита изменений продукции
CREATE TRIGGER tr_Products_Audit
ON Products
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO AuditLog (TableName, RecordID, Operation, UserName, ChangeDate, OldValue, NewValue)
    SELECT 
        'Products',
        ISNULL(i.ProductID, d.ProductID),
        CASE 
            WHEN d.ProductID IS NULL THEN 'INSERT'
            WHEN i.ProductID IS NULL THEN 'DELETE'
            ELSE 'UPDATE' 
        END,
        SYSTEM_USER,
        GETDATE(),
        (SELECT d.ProductID, d.ArticleNumber, d.ProductName, d.TechnicalParameters 
         FROM deleted d FOR JSON PATH),
        (SELECT i.ProductID, i.ArticleNumber, i.ProductName, i.TechnicalParameters 
         FROM inserted i FOR JSON PATH)
    FROM inserted i
    FULL OUTER JOIN deleted d ON i.ProductID = d.ProductID;
END;
GO

-- 5. Процедура формирования отчета по остаткам
CREATE PROCEDURE sp_GenerateInventoryReport
    @Date DATE = NULL,
    @WarehouseID INT = NULL,
    @ProductCategoryID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @Date IS NULL SET @Date = GETDATE();
    
    SELECT 
        p.ArticleNumber,
        p.ProductName,
        pc.CategoryName,
        w.Name AS WarehouseName,
        sc.CellCode,
        pp.Quantity,
        b.BatchNumber,
        b.CreationDate,
        b.ExpirationDate,
        bs.StatusName AS BatchStatus
    FROM Products p
    JOIN ProductCategories pc ON p.ProductCategoryID = pc.CategoryID
    JOIN ProductPlacements pp ON pp.BatchID IN (SELECT BatchID FROM Batches WHERE ProductID = p.ProductID)
    JOIN StorageCells sc ON pp.CellID = sc.CellID
    JOIN Warehouses w ON sc.WarehouseID = w.WarehouseID
    JOIN Batches b ON pp.BatchID = b.BatchID
    JOIN BatchStatuses bs ON b.StatusID = bs.StatusID
    WHERE pp.Quantity > 0
    AND (@WarehouseID IS NULL OR w.WarehouseID = @WarehouseID)
    AND (@ProductCategoryID IS NULL OR p.ProductCategoryID = @ProductCategoryID)
    ORDER BY pc.CategoryName, p.ProductName, w.Name, sc.CellCode;
END;
GO