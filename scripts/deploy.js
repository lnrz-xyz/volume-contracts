/* eslint-disable no-undef */
async function main() {
  const factory = await ethers.getContractAt(
    "VolumeFactory",
    "0x6571Da2e10C9bf60b1DC5C3d6E8F572a93867e59"
  )

  const tx = await factory.createVolumeToken("Volume", "ART", {
    value: ethers.utils.parseEther("0.0004"),
  })

  const res = await tx.wait()

  console.log("Res: ", res.transactionHash)
  // print the address of the first log
  console.log("First log: ", res.logs[0].address)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
