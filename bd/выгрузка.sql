-- Процедура выгрузки данных в 1С
CREATE PROCEDURE sp_ExportTo1C
    @StartDate DATE,
    @EndDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Выгрузка продукции
    SELECT 
        p.ArticleNumber AS Код,
        p.ProductName AS Наименование,
        pc.CategoryName AS Категория,
        p.TechnicalParameters AS Характеристики
    FROM Products p
    JOIN ProductCategories pc ON p.ProductCategoryID = pc.CategoryID
    WHERE p.IsActive = 1
    FOR XML PATH('Продукция'), ROOT('ВыгрузкаПродукции');
    
    -- Выгрузка движений
    SELECT 
        pt.TransactionDate AS Дата,
        pt.TransactionType AS Операция,
        p.ArticleNumber AS КодПродукции,
        p.ProductName AS Продукция,
        pt.Quantity AS Количество,
        ISNULL(fw.Code + '-' + fc.CellCode, '') AS СкладОтправитель,
        ISNULL(tw.Code + '-' + tc.CellCode, '') AS СкладПолучатель,
        pt.DocumentNumber AS Документ
    FROM ProductTransactions pt
    JOIN Batches b ON pt.BatchID = b.BatchID
    JOIN Products p ON b.ProductID = p.ProductID
    LEFT JOIN StorageCells fc ON pt.FromCellID = fc.CellID
    LEFT JOIN Warehouses fw ON fc.WarehouseID = fw.WarehouseID
    LEFT JOIN StorageCells tc ON pt.ToCellID = tc.CellID
    LEFT JOIN Warehouses tw ON tc.WarehouseID = tw.WarehouseID
    WHERE pt.TransactionDate BETWEEN @StartDate AND @EndDate
    ORDER BY pt.TransactionDate
    FOR XML PATH('Движение'), ROOT('ВыгрузкаДвижений');
END;
GO

-- Процедура формирования XML для ERP
CREATE PROCEDURE sp_GenerateERPXML
    @Date DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @Date IS NULL SET @Date = GETDATE();
    
    DECLARE @XML XML;
    
    SET @XML = (
        SELECT 
            (SELECT 
                w.Code AS '@Код',
                w.Name AS '@Наименование',
                (SELECT
                    sc.CellCode AS '@Ячейка',
                    p.ArticleNumber AS '@КодПродукции',
                    p.ProductName AS '@Продукция',
                    pp.Quantity AS '@Количество',
                    b.BatchNumber AS '@Партия',
                    FORMAT(b.CreationDate, 'yyyy-MM-dd') AS '@ДатаИзготовления'
                FROM ProductPlacements pp
                JOIN StorageCells sc ON pp.CellID = sc.CellID
                JOIN Batches b ON pp.BatchID = b.BatchID
                JOIN Products p ON b.ProductID = p.ProductID
                WHERE sc.WarehouseID = w.WarehouseID
                AND pp.Quantity > 0
                FOR XML PATH('Позиция'), TYPE)
            FROM Warehouses w
            WHERE w.IsActive = 1
            FOR XML PATH('Склад'), TYPE)
        FOR XML PATH('Остатки'), ROOT('Выгрузка')
    );
    
    SELECT @XML AS ResultXML;
END;
GO