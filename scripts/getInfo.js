/* eslint-disable no-undef */
async function main() {
  const contract = await ethers.getContractAt(
    "VolumeToken",
    "0xaba0c86aa3de03bd3f1178e8e3c2b526766332da"
  )

  const info = await contract.balanceOf(
    "0xaba0c86aa3de03bd3f1178e8e3c2b526766332da"
  )
  const volume = await contract.volume()

  console.log("Info:", ethers.utils.formatEther(info))
  console.log("Volume:", ethers.utils.formatEther(volume))
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
