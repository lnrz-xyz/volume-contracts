/* eslint-disable no-undef */

async function main() {
  const contract = await ethers.getContractAt(
    "VolumeToken",
    "0xea952c2af9dddfbf30d7bbbc0845a7c7896f581d"
  )

  // const buyPrice = await contract.getBuyPrice(
  //   ethers.utils.parseEther("800000000")
  // )
  // console.log("BuyPrice: ", ethers.utils.formatEther(buyPrice))

  // const buyAmount = await contract.getAmountByETHBuy(
  //   ethers.utils.parseEther("0.25"),
  //   0
  // )
  // console.log("BuyAmount: ", ethers.utils.formatEther(buyAmount))

  // // get top holders
  // const topHolders = await contract.topHolders(0)
  // console.log("TopHolders: ", topHolders)

  // const threshold = await contract.liquidityPoolVolumeThreshold()
  // console.log("Paused: ", ethers.utils.formatEther(threshold))

  // const currentTokensInCurve = await contract.getTokensHeldInCurve()
  // console.log(
  //   "CurrentTokensInCurve: ",
  //   ethers.utils.formatEther(currentTokensInCurve)
  // )
  // const sellPriceTokensInCurve =
  //   await contract.getSellPrice(currentTokensInCurve)
  // console.log(
  //   "SellPriceTokensInCurve: ",
  //   ethers.utils.formatEther(sellPriceTokensInCurve)
  // )

  // const sellPriceEverything = await contract.getSellPrice(0)
  // console.log(
  //   "SellPriceEverything: ",
  //   ethers.utils.formatEther(sellPriceEverything)
  // )
  // const balanceOfMe = await contract.balanceOf(
  //   "0x49D4de8Fc7fD8FceEf03AA5b7b191189bFbB637b"
  // )
  // console.log("BalanceOfMe: ", ethers.utils.formatEther(balanceOfMe))

  // const sellPriceMe = await contract.getSellPrice(balanceOfMe)
  // console.log("SellPriceMe: ", ethers.utils.formatEther(sellPriceMe))

  // const buyPrice = await contract.getBuyPrice(ethers.utils.parseEther("1"))
  // console.log("BuyPrice: ", ethers.utils.formatEther(buyPrice))

  // const tx = await contract.buy(ethers.utils.parseEther("1"), 100, {
  //   value: buyPrice,
  // })

  // console.log("Tx: ", tx.hash)

  // const res = await tx.wait()
  // console.log("Res: ", res)

  // now sell with 0n as the input
  const sellPrice = await contract.getSellPrice(0)
  console.log("SellPrice: ", ethers.utils.formatEther(sellPrice))

  const tx2 = await contract.sell(0, 0)
  console.log("Tx2: ", tx2.hash)

  const res2 = await tx2.wait()
  console.log("Res2: ", res2)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
