/* eslint-disable no-undef */
async function main() {
    const Contract = await ethers.getContractFactory('VolumeToken');

    const contract = await Contract.deploy(
        process.env.UNISWAP_FACTORY,
        process.env.UNISWAP_ROUTER,
        process.env.UNISWAP_POSITIONS,
        process.env.WETH,
        'Volume',
        'ART'
    );

    console.log('Contract deployed to address:', contract.target);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
