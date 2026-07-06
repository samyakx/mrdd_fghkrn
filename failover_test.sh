#!/bin/bash
DOMAIN="www.testmrdd.kamikazian.com"
PRIMARY_BUCKET="www.testmrdd.kamikazian.com"

echo "=== MRDD Failover Test Log ===" > test_results.log
echo "Started at: $(date)" >> test_results.log

echo -e "\n=== 1. Pre-Failover Check ===" >> test_results.log
echo "Current DNS Resolution:" >> test_results.log
dig +short $DOMAIN >> test_results.log
curl -w "Response Time: %{time_total}s\n" -s -o /dev/null http://$DOMAIN/ >> test_results.log

echo -e "\n=== 2. Simulating Failure in Primary Region ===" >> test_results.log
echo "Action: Deleting index.html from primary bucket..." >> test_results.log
aws s3 rm s3://$PRIMARY_BUCKET/index.html

echo -e "\n=== 3. Monitoring Failover (Pinging every 10 seconds) ===" >> test_results.log
for i in {1..15}; do
  echo "--- [Attempt $i] Time: $(date +%H:%M:%S) ---" >> test_results.log
  IP=$(dig +short $DOMAIN | tail -n 1)
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$DOMAIN/)
  RESP_TIME=$(curl -s -o /dev/null -w "%{time_total}s" http://$DOMAIN/)
  
  echo "Resolved To: $IP" >> test_results.log
  echo "HTTP Status: $HTTP_STATUS (Note: 404/403 means S3 is rejecting it, which is expected for secondary)" >> test_results.log
  echo "Response Time: $RESP_TIME" >> test_results.log
  
  sleep 10
done

echo -e "\n=== 4. Restoring Primary Region ===" >> test_results.log
aws s3 cp /Users/apple/Documents/MRDD_agy/primary/index.html s3://$PRIMARY_BUCKET/index.html

echo -e "\n=== Test Complete ===" >> test_results.log
