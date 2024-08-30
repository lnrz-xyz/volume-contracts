/* eslint-disable no-undef */
async function main() {
  const factory = await ethers.getContractAt(
    "VolumeFactory",
    "0x3fbB85543dFa58D23e31Cd02759f76A80c6EA8C0"
  )

  const tx = await factory.createVolumeToken("Volume", "ART", {
    value: ethers.utils.parseEther("0.0004"),
  })

  const res = await tx.wait()

  console.log("Res: ", res.transactionHash)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
