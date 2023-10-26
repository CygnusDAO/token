# CYG Token Rewarder

The Pillars Of Creation is a contract that allows borrowers and lenders to collect CYG based on how much they have deposited at the core contracts.
Borrowers accrue CYG rewards based on their borrowed amount, while lenders accrue CYG rewards based on their deposited USD amount.

The CYG emissions per block is based on the total amount of CYG rewards, the total number of epochs and an emissions curve that reduces each epoch's emissions by 2.5% until it reaches its planned death. 

```javascript
  totalCygAtN = ((totalRewards - accumulatedRewards) * reductionFactor) / emissionsCurve(epoch)
```

where totalRewards is the total amount of rewards that will be distributed over all epochs, accumulatedRewards is the total amount of rewards that have been distributed in previous epochs, reductionFactor is the percentage by which the rewards are reduced every epoch, and emissionsCurve(epoch) is the function that returns the curve.

The emissions curve is calculated using the following formula:

emissionsCurve(epoch) = (1 - reductionFactor)^epoch

where reductionFactor is the percentage by which the rewards are reduced every epoch, and epoch is the current epoch.

# Yearly Rewards

For example if we set the total token emissions to be 3,000,000, then the overall emissions will be:

<div align="Center">

|Epoch | Cyg Rewards |
|------|-------------|
| 0 - 5  |	924,647.90 |
| 6 - 11 | 658,517.38|
| 12 - 17 |	468,984.07|
| 18 - 23 |	334,001.90 |
| 24 - 29 | 237,870.07 |
| 30 - 35 |	169,406.72 |
| 36 - 41	| 120,648.38 |
| 41 - 47	| 85,923.58 |
|	TOTAL   | 3,000,000|

</div>

# Epoch Rewards

With total token emissions of 3,000,000 the per epoch emissions as computed by the contract will be:

<div align="center">

| Epoch | Cyg Per Block | Cyg Rewards |
|-------|--------------|-------------|
| 1     | 0.067235     | 176,693.58   |
| 2     | 0.063537     | 166,975.44   |
| 3     | 0.060043     | 157,791.79   |
| 4     | 0.056740     | 149,113.24   |
| 5     | 0.053619     | 140,912.01   |
| 6     | 0.050670     | 133,161.85   |
| 7     | 0.047884     | 125,837.95   |
| 8     | 0.045250     | 118,916.86   |
| 9     | 0.042761     | 112,376.43   |
| 10    | 0.040409     | 106,195.73   |
| 11    | 0.038187     | 100,354.96   |
| 12    | 0.036087     | 94,835.44    |
| 13    | 0.034102     | 89,619.49    |
| 14    | 0.032226     | 84,690.42    |
| 15    | 0.030454     | 80,032.45    |
| 16    | 0.028779     | 75,630.66    |
| 17    | 0.027196     | 71,470.98    |
| 18    | 0.025700     | 67,540.07    |
| 19    | 0.024287     | 63,825.37    |
| 20    | 0.022951     | 60,314.97    |
| 21    | 0.021689     | 56,997.65    |
| 22    | 0.020496     | 53,862.78    |
| 23    | 0.019368     | 50,900.33    |
| 24    | 0.018303     | 48,100.81    |
| 25    | 0.017297     | 45,455.26    |
| 26    | 0.016345     | 42,955.22    |
| 27    | 0.015446     | 40,592.69    |
| 28    | 0.014597     | 38,360.09    |
| 29    | 0.013794     | 36,250.28    |
| 30    | 0.013035     | 34,256.52    |
| 31    | 0.012318     | 32,372.41    |
| 32    | 0.011641     | 30,591.93    |
| 33    | 0.011001     | 28,909.37    |
| 34    | 0.010395     | 27,319.36    |
| 35    | 0.009824     | 25,816.79    |
| 36    | 0.009283     | 24,396.87    |
| 37    | 0.008773     | 23,055.04    |
| 38    | 0.008290     | 21,787.01    |
| 39	  | 0.007834	   | 20,588.73    |
|40	    | 0.007403     | 19,456.35    |
|41	    | 0.006991     | 18,386.25    |
|42	    | 0.00661      | 17,375.00    |
|43	    | 0.00624	     | 16,419.38    |
|44	    | 0.00590	     | 15,516.31    |
|45    	| 0.00557	     | 14,662.92    |
|46     | 0.00527	     | 13,856.46    |
|47	    | 0.00498	     | 13,094.35    |
|48     |	0.00470      | 12,374.16    |
|       |              | 3,000,000.00 |

</div>

# Collecting CYG Rewards

TODO: Example of collecting CYG for borrowers and lenders
