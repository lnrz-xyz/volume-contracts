/* eslint-disable no-undef */

const { parseEther } = require("ethers/lib/utils")

async function main() {
  const contract = await ethers.getContractAt(
    "VolumeToken",
    "0x3304eE0d47C7f01A877F319FB4dd14C158963518"
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

  const paused = await contract.paused()
  console.log("Paused: ", paused)

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

  // const threshold = await contract.liquidityPoolVolumeThreshold()
  // console.log("Threshold: ", ethers.utils.formatEther(threshold))

  // const buyAmount = await contract.getAmountByETHBuy(threshold, 0)
  // console.log("BuyAmount: ", ethers.utils.formatEther(buyAmount))

  // const tx = await contract.buy(buyAmount, 0, {
  //   value: threshold,
  // })

  const buyAmount = await contract.getAmountByETHBuy(parseEther("0.001"), 0)
  console.log("BuyAmount: ", buyAmount)

  const plusFee = parseEther("0.001").mul(105).div(100)
  console.log("PlusFee: ", ethers.utils.formatEther(plusFee))

  const tx = await contract.buy(buyAmount, 0, {
    value: plusFee,
  })

  console.log("Tx: ", tx.hash)
  await tx.wait()

  // do it again and check the new price
  const buyPriceOfAmount = await contract.getBuyPrice(buyAmount)
  console.log("BuyPriceOfAmount: ", ethers.utils.formatEther(buyPriceOfAmount))

  const buyAgainPlusFee = buyPriceOfAmount.mul(105).div(100)
  console.log("BuyAgainPlusFee: ", ethers.utils.formatEther(buyAgainPlusFee))

  const buyAgainTx = await contract.buy(buyAmount, 0, {
    value: buyAgainPlusFee,
  })

  console.log("BuyAgainTx: ", buyAgainTx.hash)
  await buyAgainTx.wait()

  // see the sell price of new amount it should be higher than the original buy price
  const sellPriceOfAmount = await contract.getSellPrice(buyAmount)
  console.log(
    "SellPriceOfAmount: ",
    ethers.utils.formatEther(sellPriceOfAmount)
  )

  // sell the tokens
  const sellTx = await contract.sell(buyAmount, 0)
  console.log("SellTx: ", sellTx.hash)
  await sellTx.wait()
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
