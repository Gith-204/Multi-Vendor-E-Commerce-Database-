# Multi-Vendor E-Commerce Analytics & Inventory Management System

A production-grade relational database engineered in PostgreSQL to support a high-concurrency marketplace. The system mimics a combined Amazon and Flipkart seller ecosystem, featuring complete multi-vendor profile tracking, real-time multi-warehouse inventory tracking, transactional order safety loops, automated invoices, coupons, and comprehensive financial/operational analytical reporting dashboards.

Key Features & Modules

* User Management: Secure role-based identity management handling Customer, Seller, and Admin lifecycle profiles.
  
* Product Catalogue: Hierarchical multi-level categories, verified brand registries, and multi-image galleries per product SKU.
  
* Inventory & Warehouses: Multi-warehouse physical stock tracking with automated audit logs ('stock_movements') tracking outward, incoming, returned, and damaged stock.
  
* Order & Cart Processing: Concurrency-locked shopping sessions, snapshotted transactional line-item logging, and status state tracking.
  
* Financial Ledger & Discounts: Automated invoice compilation, gateway reference matching, dynamic transaction status logs, and valid coupon deduction logic.
  
* Quality Assurance: Moderated rating reviews, helpful vote triggers, and complete cross-transactional return/refund operations. 

