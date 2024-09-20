/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "BancorFormula",
    "0xd50CA017B38132101185Ff6B043122FFa9814E55"
  )

  const price = await contract.calculatePurchaseReturn(
    ethers.utils.parseEther("1"),
    1n,
    465552,
    ethers.utils.parseEther("3")
  )

  console.log("Price:", ethers.utils.formatEther(price))
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
