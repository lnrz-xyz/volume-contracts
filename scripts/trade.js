/* eslint-disable no-undef */

async function main() {
  const contract = await ethers.getContractAt(
    "VolumeToken",
    "0xC9F2BF2ed936a1743e62b7997FeBAc5EfD8e851e"
  )

  const buyPrice = await contract.getBuyPrice(
    ethers.utils.parseEther("500000000")
  )
  console.log("BuyPrice: ", ethers.utils.formatEther(buyPrice))

  const buyAmount = await contract.getAmountByETHBuy(
    ethers.utils.parseEther("0.1"),
    0
  )
  console.log("BuyAmount: ", ethers.utils.formatEther(buyAmount))

  // const tx = await contract.buy(parseEther('2100000'), 100, {
  //     value: buyPrice,
  // });

  // console.log('Tx: ', tx.hash);

  // const res = await tx.wait();
  // console.log('Res: ', res);

  // const finalTx = await contract.createAndMintLiquidity()

  // console.log("FinalTx: ", finalTx.hash)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
