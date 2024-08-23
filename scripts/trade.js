/* eslint-disable no-undef */
const { parseEther, formatEther } = require('ethers');

async function main() {
    const contract = await ethers.getContractAt('VolumeToken', '0xe1EcF1DbffFDd67105b5D48B64fc2c7dfed348B9');

    const buyPrice = await contract.getBuyPrice(parseEther('2100000'));
    console.log('BuyPrice: ', formatEther(buyPrice));

    const tx = await contract.buy(parseEther('2100000'), 100, {
        value: buyPrice,
    });

    console.log('Tx: ', tx.hash);

    const res = await tx.wait();
    console.log('Res: ', res);

    // const finalTx = await contract.createAndMintLiquidity()

    // console.log("FinalTx: ", finalTx.hash)
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
