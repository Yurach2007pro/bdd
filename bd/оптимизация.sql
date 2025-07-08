-- Секционирование таблицы ProductTransactions по датам
CREATE PARTITION FUNCTION pf_TransactionDate (DATE)
AS RANGE RIGHT FOR VALUES 
('2025-01-01', '2025-04-01', '2025-07-01', '2025-10-01');

CREATE PARTITION SCHEME ps_TransactionDate
AS PARTITION pf_TransactionDate
TO (fg_Transactions_2024Q4, fg_Transactions_2025Q1, 
    fg_Transactions_2025Q2, fg_Transactions_2025Q3, 
    fg_Transactions_2025Q4);

CREATE CLUSTERED INDEX CIX_ProductTransactions_Date
ON ProductTransactions(TransactionDate)
ON ps_TransactionDate(TransactionDate);

-- Columnstore индекс для аналитических запросов
CREATE NONCLUSTERED COLUMNSTORE INDEX NCI_InventoryAnalytics
ON ProductPlacements (PlacementID, BatchID, CellID, Quantity)
WHERE Quantity > 0;

-- Оптимизированные индексы для часто используемых запросов
CREATE INDEX IX_Products_Search ON Products(ProductCategoryID, IsActive)
INCLUDE (ProductName, ArticleNumber, WarrantyMonths);

CREATE INDEX IX_Batches_Product_Status ON Batches(ProductID, StatusID)
INCLUDE (Quantity, CreationDate);