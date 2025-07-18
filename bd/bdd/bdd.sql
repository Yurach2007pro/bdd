-- Создание базы данных
CREATE DATABASE ProductionAccounting;
USE ProductionAccounting;

-- 1. Таблица видов продукции
CREATE TABLE Products (
    ProductID INT PRIMARY KEY AUTO_INCREMENT,
    ProductName VARCHAR(100) NOT NULL,
    ProductCode VARCHAR(20) UNIQUE,
    Description TEXT,
    UnitOfMeasure VARCHAR(20) NOT NULL, -- штуки, кг, литры и т.д.
    StandardCost DECIMAL(10, 2),
    SellingPrice DECIMAL(10, 2),
    IsActive BOOLEAN DEFAULT TRUE,
    CreatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 2. Таблица склада (учет остатков)
CREATE TABLE Warehouse (
    WarehouseID INT PRIMARY KEY AUTO_INCREMENT,
    ProductID INT NOT NULL,
    Quantity DECIMAL(10, 3) NOT NULL DEFAULT 0,
    LastUpdated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);

-- 3. Таблица производственных партий
CREATE TABLE ProductionBatches (
    BatchID INT PRIMARY KEY AUTO_INCREMENT,
    ProductID INT NOT NULL,
    BatchNumber VARCHAR(50) NOT NULL,
    ProductionDate DATE NOT NULL,
    ExpiryDate DATE,
    QuantityProduced DECIMAL(10, 3) NOT NULL,
    ProductionCost DECIMAL(10, 2),
    Status ENUM('В процессе', 'Завершено', 'Забраковано') DEFAULT 'В процессе',
    Notes TEXT,
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);

-- 4. Таблица перемещений на склад
CREATE TABLE WarehouseMovements (
    MovementID INT PRIMARY KEY AUTO_INCREMENT,
    BatchID INT NOT NULL,
    MovementDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    Quantity DECIMAL(10, 3) NOT NULL,
    MovementType ENUM('Поступление', 'Списание', 'Корректировка') NOT NULL,
    Reason VARCHAR(255),
    EmployeeID INT, -- ссылка на таблицу сотрудников
    FOREIGN KEY (BatchID) REFERENCES ProductionBatches(BatchID)
);

-- 5. Таблица продаж
CREATE TABLE Sales (
    SaleID INT PRIMARY KEY AUTO_INCREMENT,
    SaleDate DATETIME DEFAULT CURRENT_TIMESTAMP,
    CustomerID INT, -- ссылка на таблицу клиентов
    InvoiceNumber VARCHAR(50),
    TotalAmount DECIMAL(12, 2),
    Status ENUM('Оформлен', 'Оплачен', 'Отгружен', 'Отменен') DEFAULT 'Оформлен'
);

-- 6. Таблица позиций продаж
CREATE TABLE SaleItems (
    SaleItemID INT PRIMARY KEY AUTO_INCREMENT,
    SaleID INT NOT NULL,
    ProductID INT NOT NULL,
    BatchID INT,
    Quantity DECIMAL(10, 3) NOT NULL,
    UnitPrice DECIMAL(10, 2) NOT NULL,
    TotalPrice DECIMAL(10, 2) NOT NULL,
    FOREIGN KEY (SaleID) REFERENCES Sales(SaleID),
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID),
    FOREIGN KEY (BatchID) REFERENCES ProductionBatches(BatchID)
);

-- 7. Таблица рецептур (если продукция состоит из компонентов)
CREATE TABLE Recipes (
    RecipeID INT PRIMARY KEY AUTO_INCREMENT,
    ProductID INT NOT NULL,
    ComponentID INT NOT NULL, -- ссылка на таблицу материалов/компонентов
    Quantity DECIMAL(10, 3) NOT NULL,
    UnitOfMeasure VARCHAR(20) NOT NULL,
    Notes TEXT,
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);

-- Триггер при поступлении на склад
DELIMITER //
CREATE TRIGGER after_warehouse_movement_insert
AFTER INSERT ON WarehouseMovements
FOR EACH ROW
BEGIN
    IF NEW.MovementType = 'Поступление' THEN
        UPDATE Warehouse 
        SET Quantity = Quantity + NEW.Quantity
        WHERE ProductID = (SELECT ProductID FROM ProductionBatches WHERE BatchID = NEW.BatchID);
    ELSEIF NEW.MovementType = 'Списание' THEN
        UPDATE Warehouse 
        SET Quantity = Quantity - NEW.Quantity
        WHERE ProductID = (SELECT ProductID FROM ProductionBatches WHERE BatchID = NEW.BatchID);
    END IF;
END//
DELIMITER ;

-- Триггер при продаже продукции
DELIMITER //
CREATE TRIGGER after_sale_item_insert
AFTER INSERT ON SaleItems
FOR EACH ROW
BEGIN
    UPDATE Warehouse 
    SET Quantity = Quantity - NEW.Quantity
    WHERE ProductID = NEW.ProductID;
END//
DELIMITER ;