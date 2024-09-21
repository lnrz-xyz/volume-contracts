/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "CurveCalculator",
    "0x853F3b97215d0CbeB84f5201586f9ff11169524b"
  )

  const K = await contract.calculateConstant(
    ethers.utils.parseEther("3"),
    ethers.utils.parseEther("400000000") // 400M
  )
  console.log("K:", K)

  const price = await contract.getBuyPrice(
    ethers.utils.parseEther("400000000"),
    0,
    K
  )

  console.log("Price:", ethers.utils.formatEther(price))
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
