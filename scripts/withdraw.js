/* eslint-disable no-undef */
async function main() {
    const contract = await ethers.getContractAt('VolumeToken', '0x1BFd07fF6ceeF8DF7F6Ac09B883107B0f394eB6B');

    await contract.testWithdrawRemoveBeforeProd();
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
