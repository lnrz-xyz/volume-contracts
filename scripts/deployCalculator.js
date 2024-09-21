/* eslint-disable no-undef */
async function main() {
  const Calculator = await ethers.getContractFactory("CurveCalculator")
  const calculator = await Calculator.deploy()
  console.log("Calculator deployed to address:", calculator.address)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
