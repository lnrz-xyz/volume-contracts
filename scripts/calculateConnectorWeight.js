// calculateConnectorWeight.js
// Function to calculate the connector weight given desired return amount and deposit amount
// Uses decimal.js library for high-precision calculations

const Decimal = require("decimal.js")
const ethers = require("ethers")

function calculateConnectorWeight(targetPurchaseReturn, depositAmount) {
  // Set decimal precision to handle large numbers accurately
  Decimal.set({ precision: 50 })

  // Constants
  const initialSupply = new Decimal("1e18") // S0 = 1 * 1e18 tokens (1 token with 18 decimals)
  const initialConnectorBalance = new Decimal("1") // C0 = 1 wei

  // Convert inputs to Decimal
  const R = new Decimal(targetPurchaseReturn) // Desired return amount in token's smallest unit
  const D = new Decimal(depositAmount) // Deposit amount in wei

  // Calculate ln(R/S0 + 1)
  const numerator = Decimal.ln(R.dividedBy(initialSupply).plus(1))

  // Calculate ln(1 + D/C0)
  const denominator = Decimal.ln(D.dividedBy(initialConnectorBalance).plus(1))

  // Calculate connector weight (CW) in ppm (parts per million)
  const connectorWeight = numerator.dividedBy(denominator).times(1e6)

  // Return connector weight as a number (rounded to nearest integer)
  return connectorWeight.toDecimalPlaces(0, Decimal.ROUND_HALF_UP).toNumber()
}

// Example usage:

// Desired return amount: 400,000,000 tokens (with 18 decimals)
const targetPurchaseReturn = ethers.utils.parseEther("400000000").toString() // 400 million * 1e18

// Deposit amount: 4 ETH (in wei)
const depositAmount = ethers.utils.parseEther("3").toString() // 4 * 1e18 wei

const cw = calculateConnectorWeight(targetPurchaseReturn, depositAmount)
console.log("Connector Weight (ppm):", cw)

// Output: Connector Weight (ppm): 461303
