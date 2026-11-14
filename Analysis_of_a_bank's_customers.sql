/* SOURCE TABLES
   Inspect the main tables used to build the customer-level features.
*/
SELECT * FROM banca.cliente;
SELECT * FROM banca.conto;
SELECT * FROM banca.tipo_conto;
SELECT * FROM banca.tipo_transazione;
SELECT * FROM banca.transazioni;

/* TRANSACTION INDICATORS
   Calculate the number and total amount of incoming and outgoing
   transactions for each bank account.
*/
-- Aggregate outgoing transactions by account
DROP TABLE IF EXISTS banca.totale_uscite;
CREATE TEMPORARY TABLE banca.totale_uscite AS
SELECT
    t.id_conto,
    COUNT(*) AS numero_transazioni_uscita,
    ROUND(SUM(ABS(t.importo)), 2) AS importo_totale_uscita
FROM banca.transazioni t
INNER JOIN banca.tipo_transazione tt
    ON t.id_tipo_trans = tt.id_tipo_transazione
WHERE tt.segno = '-'
GROUP BY t.id_conto;
SELECT * FROM banca.totale_uscite;

-- Aggregate incoming transactions by account
DROP TABLE IF EXISTS banca.totale_entrate;
CREATE TEMPORARY TABLE banca.totale_entrate AS
SELECT
    t.id_conto,
    COUNT(*) AS numero_transazioni_entrata,
    ROUND(SUM(ABS(t.importo)), 2) AS importo_totale_entrata
FROM banca.transazioni t
INNER JOIN banca.tipo_transazione tt
    ON t.id_tipo_trans = tt.id_tipo_transazione
WHERE tt.segno = '+'
GROUP BY t.id_conto;
SELECT * FROM banca.totale_entrate;

/* ACCOUNT INDICATORS
   Calculate the number of accounts held by each customer,
   including a breakdown by account type.
*/
DROP TABLE IF EXISTS banca.numero_conti;
CREATE TEMPORARY TABLE banca.numero_conti AS
SELECT
    id_cliente,
    
    -- Total number of accounts held by the customer
    COUNT(id_conto) AS numero_totale_conti,
    
    -- Number of accounts by account type
    COUNT(CASE
		WHEN id_tipo_conto = 0 THEN id_conto
        END) AS numero_conti_conto_base,
        
    COUNT(CASE
		WHEN id_tipo_conto = 1 THEN id_conto
        END) AS numero_conti_conto_business,
        
    COUNT(CASE
		WHEN id_tipo_conto = 2 THEN id_conto
        END) AS numero_conti_conto_privati,
        
    COUNT(CASE
		WHEN id_tipo_conto = 3 THEN id_conto
        END) AS numero_conti_conto_famiglie
        
FROM banca.conto
GROUP BY id_cliente;

/* ACCOUNT-LEVEL CUSTOMER SUMMARY
   Combine customer information, account characteristics and
   transaction indicators into one row per customer-account combination.
*/
DROP TABLE IF EXISTS banca.riepilogo_cliente_conti;
CREATE TEMPORARY TABLE banca.riepilogo_cliente_conti AS
SELECT
    c.id_cliente,
    c.nome,
    c.cognome,
    c.data_nascita,
    cto.id_conto,
    cto.id_tipo_conto,
    nc.numero_totale_conti,
    nc.numero_conti_conto_base,
    nc.numero_conti_conto_business,
    nc.numero_conti_conto_privati,
    nc.numero_conti_conto_famiglie,
    
    COALESCE(tu.numero_transazioni_uscita, 0) AS numero_transazioni_uscita,
    COALESCE(te.numero_transazioni_entrata, 0) AS numero_transazioni_entrata,
    COALESCE(tu.importo_totale_uscita, 0) AS importo_totale_uscita,
    COALESCE(te.importo_totale_entrata, 0) AS importo_totale_entrata
    
FROM banca.cliente c
LEFT JOIN banca.conto cto ON c.id_cliente = cto.id_cliente
LEFT JOIN banca.numero_conti nc ON c.id_cliente = nc.id_cliente
LEFT JOIN banca.totale_uscite tu ON cto.id_conto = tu.id_conto
LEFT JOIN banca.totale_entrate te ON cto.id_conto = te.id_conto;

/* CUSTOMER-LEVEL FEATURES
   Aggregate account-level information to obtain one row per customer.
*/
DROP TABLE IF EXISTS banca.features_cliente;
CREATE TABLE banca.features_cliente AS
SELECT
    id_cliente,
    nome,
    cognome,
    data_nascita,
    COUNT(DISTINCT id_conto) AS numero_totale_conti,
    
    -- Account-type counts are repeated for each account, so MAX retrieves the customer-level value after grouping by customer.
    COALESCE(MAX(numero_conti_conto_base), 0) AS numero_conti_conto_base,
    COALESCE(MAX(numero_conti_conto_business), 0) AS numero_conti_conto_business,
    COALESCE(MAX(numero_conti_conto_privati), 0) AS numero_conti_conto_privati,
    COALESCE(MAX(numero_conti_conto_famiglie), 0) AS numero_conti_conto_famiglie,
    
    COALESCE(SUM(numero_transazioni_uscita), 0) AS numero_transazioni_uscita,
    COALESCE(SUM(numero_transazioni_entrata), 0) AS numero_transazioni_entrata,
    COALESCE(ROUND(SUM(importo_totale_uscita), 2), 0) AS importo_totale_uscita,
    COALESCE(ROUND(SUM(importo_totale_entrata), 2), 0) AS importo_totale_entrata
    
FROM banca.riepilogo_cliente_conti
GROUP BY 1,2,3,4;

/* TRANSACTION METRICS BY ACCOUNT TYPE
   Calculate transaction counts and total amounts for each account type,
   separating incoming and outgoing transactions.
*/
DROP TABLE IF EXISTS banca.movimenti_cliente_per_tipo_conto;
CREATE TEMPORARY TABLE banca.movimenti_cliente_per_tipo_conto AS
SELECT
    c.id_cliente,
    
    -- Number of incoming transactions
	SUM(CASE
		WHEN c.id_tipo_conto = 0 AND tt.segno = '+' THEN 1 ELSE 0
        END) AS numero_entrate_conto_base,
        
    SUM(CASE
		WHEN c.id_tipo_conto = 1 AND tt.segno = '+' THEN 1 ELSE 0
        END) AS numero_entrate_conto_business,
        
    SUM(CASE
		WHEN c.id_tipo_conto = 2 AND tt.segno = '+' THEN 1 ELSE 0
        END) AS numero_entrate_conto_privati,
        
    SUM(CASE
        WHEN c.id_tipo_conto = 3 AND tt.segno = '+' THEN 1 ELSE 0
        END) AS numero_entrate_conto_famiglie,

	-- Number of outgoing transactions
    SUM(CASE
        WHEN c.id_tipo_conto = 0 AND tt.segno = '-' THEN 1 ELSE 0
        END) AS numero_uscite_conto_base,
        
    SUM(CASE
        WHEN c.id_tipo_conto = 1 AND tt.segno = '-' THEN 1 ELSE 0
		END) AS numero_uscite_conto_business,
        
    SUM(CASE
        WHEN c.id_tipo_conto = 2 AND tt.segno = '-' THEN 1 ELSE 0
        END) AS numero_uscite_conto_privati,
        
    SUM(CASE
        WHEN c.id_tipo_conto = 3 AND tt.segno = '-' THEN 1 ELSE 0
        END) AS numero_uscite_conto_famiglie,

	-- Total incoming amount
    ROUND(SUM(CASE
				WHEN c.id_tipo_conto = 0 AND tt.segno = '+' THEN ABS(t.importo) ELSE 0
				END), 2) AS importo_entrate_conto_base,
                
    ROUND(SUM(CASE
				WHEN c.id_tipo_conto = 1 AND tt.segno = '+' THEN ABS(t.importo) ELSE 0
				END), 2) AS importo_entrate_conto_business,
                
    ROUND(SUM(CASE
				WHEN c.id_tipo_conto = 2 AND tt.segno = '+' THEN ABS(t.importo) ELSE 0
				END), 2) AS importo_entrate_conto_privati,
                
    ROUND(SUM(CASE
				WHEN c.id_tipo_conto = 3 AND tt.segno = '+' THEN ABS(t.importo) ELSE 0
				END), 2) AS importo_entrate_conto_famiglie,

	-- Total outgoing amount
    ROUND(SUM(CASE
				WHEN c.id_tipo_conto = 0 AND tt.segno = '-' THEN ABS(t.importo) ELSE 0
				END), 2) AS importo_uscite_conto_base,
                
    ROUND(SUM(CASE
				WHEN c.id_tipo_conto = 1 AND tt.segno = '-' THEN ABS(t.importo) ELSE 0
				END), 2) AS importo_uscite_conto_business,
                
    ROUND(SUM(CASE
				WHEN c.id_tipo_conto = 2 AND tt.segno = '-' THEN ABS(t.importo) ELSE 0
				END), 2) AS importo_uscite_conto_privati,
                
    ROUND(SUM(CASE
				WHEN c.id_tipo_conto = 3 AND tt.segno = '-' THEN ABS(t.importo) ELSE 0
				END), 2) AS importo_uscite_conto_famiglie

-- Join accounts with transactions and transaction types to classify each movement by account type and direction.                
FROM banca.conto c
INNER JOIN banca.transazioni t ON c.id_conto = t.id_conto
INNER JOIN banca.tipo_transazione tt ON t.id_tipo_trans = tt.id_tipo_transazione
GROUP BY 1;
    
/* FINAL CUSTOMER FEATURE TABLE
   Combine feature, account and transaction features into
   a single customer-level dataset for analysis or modelling.
*/
DROP TABLE IF EXISTS banca.final_table_join;
CREATE TABLE banca.final_table_join AS
SELECT

	-- Customer feature
    f.id_cliente,
    f.nome,
    f.cognome,
    f.data_nascita,

	-- Calculate current age from date of birth
    TIMESTAMPDIFF(YEAR,f.data_nascita,CURDATE()) AS eta,
	
    -- Account ownership indicators
    f.numero_totale_conti,
    f.numero_conti_conto_base,
    f.numero_conti_conto_business,
    f.numero_conti_conto_privati,
    f.numero_conti_conto_famiglie,
	
    -- General transaction indicators
    f.numero_transazioni_uscita,
    f.numero_transazioni_entrata,
    f.importo_totale_uscita,
    f.importo_totale_entrata,
	
    -- Incoming transaction counts by account type
    COALESCE(m.numero_entrate_conto_base, 0) AS numero_entrate_conto_base,
    COALESCE(m.numero_entrate_conto_business, 0) AS numero_entrate_conto_business,
    COALESCE(m.numero_entrate_conto_privati, 0) AS numero_entrate_conto_privati,
    COALESCE(m.numero_entrate_conto_famiglie, 0) AS numero_entrate_conto_famiglie,

	-- Outgoing transaction counts by account typee
    COALESCE(m.numero_uscite_conto_base, 0) AS numero_uscite_conto_base,
    COALESCE(m.numero_uscite_conto_business, 0) AS numero_uscite_conto_business,
    COALESCE(m.numero_uscite_conto_privati, 0) AS numero_uscite_conto_privati,
    COALESCE(m.numero_uscite_conto_famiglie, 0) AS numero_uscite_conto_famiglie,

	-- Incoming transaction amounts by account type
    COALESCE(m.importo_entrate_conto_base, 0) AS importo_entrate_conto_base,
    COALESCE(m.importo_entrate_conto_business, 0) AS importo_entrate_conto_business,        
    COALESCE(m.importo_entrate_conto_privati, 0)AS importo_entrate_conto_privati,
    COALESCE(m.importo_entrate_conto_famiglie, 0) AS importo_entrate_conto_famiglie,

	-- Outgoing transaction amounts by account type	
    COALESCE(m.importo_uscite_conto_base, 0) AS importo_uscite_conto_base,   
    COALESCE(m.importo_uscite_conto_business, 0) AS importo_uscite_conto_business,       
    COALESCE(m.importo_uscite_conto_privati, 0) AS importo_uscite_conto_privati,       
    COALESCE(m.importo_uscite_conto_famiglie, 0) AS importo_uscite_conto_famiglie 
    
FROM banca.features_cliente f
LEFT JOIN banca.movimenti_cliente_per_tipo_conto m ON f.id_cliente = m.id_cliente;

-- Visualization of the final table
SELECT * FROM banca.final_table_join;
