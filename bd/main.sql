-- Создание базы данных
CREATE DATABASE EnergyMera_ProductAccounting;
GO

USE EnergyMera_ProductAccounting;
GO

-- 1. Таблица категорий продукции
CREATE TABLE ProductCategories (
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName NVARCHAR(100) NOT NULL,
    CategoryCode VARCHAR(10) UNIQUE NOT NULL,
    Description NVARCHAR(500),
    ParentCategoryID INT NULL REFERENCES ProductCategories(CategoryID)
);

-- 2. Таблица продукции
CREATE TABLE Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ArticleNumber VARCHAR(20) UNIQUE NOT NULL CHECK (ArticleNumber LIKE 'EM-[0-9][0-9][0-9][0-9]-[A-Z][A-Z]'),
    ProductName NVARCHAR(100) NOT NULL,
    ProductCategoryID INT NOT NULL REFERENCES ProductCategories(CategoryID),
    TechnicalParameters NVARCHAR(MAX) NOT NULL, -- JSON с характеристиками
    ProductionNorm DECIMAL(10,2),
    MeasurementUnitID INT NOT NULL,
    WarrantyMonths INT NOT NULL DEFAULT 24,
    IsActive BIT NOT NULL DEFAULT 1,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    ModifiedAt DATETIME2 NULL,
    CONSTRAINT CHK_Warranty CHECK (WarrantyMonths BETWEEN 12 AND 120)
);

-- 3. Таблица статусов партий
CREATE TABLE BatchStatuses (
    StatusID INT IDENTITY(1,1) PRIMARY KEY,
    StatusName NVARCHAR(50) NOT NULL,
    Description NVARCHAR(255)
);

-- 4. Таблица производственных партий
CREATE TABLE Batches (
    BatchID UNIQUEIDENTIFIER DEFAULT NEWID() PRIMARY KEY,
    ProductID INT NOT NULL REFERENCES Products(ProductID),
    BatchNumber VARCHAR(20) NOT NULL UNIQUE CHECK (BatchNumber LIKE '____-__-__-___'),
    ProductionLineID INT,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    CreationDate DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    ExpirationDate DATETIME2,
    StatusID INT NOT NULL REFERENCES BatchStatuses(StatusID),
    QualityCheck BIT DEFAULT 0,
    TestResults NVARCHAR(MAX), -- JSON с результатами испытаний
    ResponsibleEmployeeID INT
);

-- 5. Таблица типов складов
CREATE TABLE WarehouseTypes (
    TypeID INT IDENTITY(1,1) PRIMARY KEY,
    TypeName NVARCHAR(50) NOT NULL,
    Description NVARCHAR(255)
);

-- 6. Таблица складов
CREATE TABLE Warehouses (
    WarehouseID INT IDENTITY(1,1) PRIMARY KEY,
    Code VARCHAR(10) UNIQUE NOT NULL,
    Name NVARCHAR(50) NOT NULL,
    WarehouseTypeID INT NOT NULL REFERENCES WarehouseTypes(TypeID),
    Location NVARCHAR(255),
    Capacity INT NOT NULL,
    CurrentOccupancy INT NOT NULL DEFAULT 0,
    TemperatureZone VARCHAR(20) CHECK (TemperatureZone IN ('Ambient', 'Cool', 'Frozen')),
    IsActive BIT NOT NULL DEFAULT 1,
    ManagerID INT,
    CONSTRAINT CHK_Capacity CHECK (CurrentOccupancy <= Capacity)
);

-- 7. Таблица ячеек хранения
CREATE TABLE StorageCells (
    CellID INT IDENTITY(1,1) PRIMARY KEY,
    WarehouseID INT NOT NULL REFERENCES Warehouses(WarehouseID),
    CellCode VARCHAR(20) NOT NULL,
    Zone CHAR(1) CHECK (Zone IN ('A', 'B', 'C')),
    MaxWeight DECIMAL(10,2),
    Dimensions NVARCHAR(50),
    UNIQUE (WarehouseID, CellCode)
);

-- 8. Таблица размещения продукции
CREATE TABLE ProductPlacements (
    PlacementID INT IDENTITY(1,1) PRIMARY KEY,
    BatchID UNIQUEIDENTIFIER NOT NULL REFERENCES Batches(BatchID),
    CellID INT NOT NULL REFERENCES StorageCells(CellID),
    Quantity INT NOT NULL,
    PlacementDate DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    EmployeeID INT
);

-- 9. Таблица операций с продукцией
CREATE TABLE ProductTransactions (
    TransactionID INT IDENTITY(1,1) PRIMARY KEY,
    TransactionType VARCHAR(20) NOT NULL CHECK (TransactionType IN ('Поступление', 'Перемещение', 'Отгрузка', 'Списание')),
    BatchID UNIQUEIDENTIFIER NOT NULL REFERENCES Batches(BatchID),
    FromCellID INT NULL REFERENCES StorageCells(CellID),
    ToCellID INT NULL REFERENCES StorageCells(CellID),
    Quantity INT NOT NULL,
    TransactionDate DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    EmployeeID INT NOT NULL,
    DocumentNumber VARCHAR(50),
    Reason NVARCHAR(255)
);

-- 10. Таблица актов брака
CREATE TABLE DefectActs (
    ActID INT IDENTITY(1,1) PRIMARY KEY,
    BatchID UNIQUEIDENTIFIER NOT NULL REFERENCES Batches(BatchID),
    ActNumber VARCHAR(20) NOT NULL UNIQUE,
    ActDate DATE NOT NULL,
    DefectTypeID INT NOT NULL,
    Quantity INT NOT NULL,
    Description NVARCHAR(MAX),
    Decision NVARCHAR(255),
    ResponsibleEmployeeID INT NOT NULL,
    ApprovedBy INT
);

-- 11. Таблица клиентов
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    ContactPerson NVARCHAR(100),
    Phone VARCHAR(20),
    Email VARCHAR(100),
    Address NVARCHAR(255),
    ContractNumber VARCHAR(50),
    ContractDate DATE
);

-- 12. Таблица отгрузок
CREATE TABLE Shipments (
    ShipmentID UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    BatchID UNIQUEIDENTIFIER NOT NULL REFERENCES Batches(BatchID),
    FromWarehouseID INT NOT NULL REFERENCES Warehouses(WarehouseID),
    ToCustomerID INT NULL REFERENCES Customers(CustomerID),
    ShipmentDate DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    ExpectedDeliveryDate DATETIME2 NULL,
    ActualDeliveryDate DATETIME2 NULL,
    Status VARCHAR(20) NOT NULL CHECK (Status IN ('Preparing', 'In Transit', 'Delivered', 'Cancelled')),
    TransportDetails NVARCHAR(200) NULL,
    InvoiceNumber VARCHAR(50),
    CONSTRAINT CHK_DeliveryDates CHECK (ExpectedDeliveryDate > ShipmentDate AND
                                      (ActualDeliveryDate IS NULL OR ActualDeliveryDate >= ShipmentDate))
);

-- Создание индексов
CREATE INDEX IX_Products_ArticleNumber ON Products(ArticleNumber);
CREATE INDEX IX_Products_Category ON Products(ProductCategoryID);
CREATE INDEX IX_Batches_Product ON Batches(ProductID);
CREATE INDEX IX_Batches_Status ON Batches(StatusID);
CREATE INDEX IX_Batches_ProductionDate ON Batches(CreationDate);
CREATE INDEX IX_Transactions_Batch ON ProductTransactions(BatchID);
CREATE INDEX IX_Transactions_Date ON ProductTransactions(TransactionDate);
CREATE INDEX IX_Shipments_Dates ON Shipments(ShipmentDate, ExpectedDeliveryDate);