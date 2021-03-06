# Project IMBA - using AWS cloud services to construct ETL pipeline and ML model deployment
1. Raw Data in csv format saved in AWS S3<br>
    - aisles.csv: 134 rows × 2 <br>
      - aisle_id(int), aisle(chr)<br>
    - departments.csv: 21 rows × 2<br>
      - department_id(int), department(chr)<br>
    - order_products.csv: 33,819,106 rows × 4<br>
      - order_id(int), product_id(int), add_to_cart_order(int), reorder(int)<br>
    - orders.csv: 3,421,083 rows × 7<br>
      - order_id(int), user_id(int), eval_set(chr), order_number(int), order_dow(int), order_hour_of_day(int), days_since_prior_order(num)<br>
    - products.csv: 49,688 rows × 4<br>
      - product_id(int), product_name(chr), aisle_id, department_id<br>
2. AWS Glue Crawler to crawl data from S3 and connect AWS Athena with Glue Data Catalog. Explore and validate the datasets using SQL queries from Athena
3. Transform the data using Lambda functions, turning raw data into feature data that will be used into ML model in the later stage<br>
   * Lambda Scripts: lambda_func_exe_query_order_prior.py, lambda_func_exe_query_user_features_1.py, lambda_func_exe_query_user_features_2.py, lambda_func_exe_query_prd_features.py, lambda_func_exe_query_up_features.py, lambda_func_exe_query_prd_features.py
4. Orchestrate the ETL process using AWS Step Function, adding a Glue job to further transfer the data. At the end of the ETL pipeline, a data file is loaded into S3.
5. Using Amazon SageMaker for model training and deployment.<br>
   * Product reordering prediction: the goal is to predict if how likely purchased products will be repurchased<br>
   * Model in use is XGboost.<br>
   * R libraries used: ProjectTemplate, tidyverse, xgboost, pROC, precrec<br>
   * The model achieved a test AUC of 0.832<br>
   * AWS SageMaker to evoke an endpoint to open for end client application to access through API Gateway<br>
6. A basic frontend application to get prediction from the trained model.

