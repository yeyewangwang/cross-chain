// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract TwoPartySwap {

    /**
    The Swap struct keeps track of participants and swap details
     */
    struct Swap {
        // assetEscrower: who escrows the asset (Alice in diagram)
        address payable assetEscrower;
        // premiumEscrower: who escrows the premium (Bob in diagram)
        address payable premiumEscrower;
        // hashLock: the hash of a secret, which only the assetEscrower knows
        bytes32 hashLock;
        // assetAddress: the ERC20 Token's address, which will be used to access accounts
        address assetAddress;
    }

    /**
    The Asset struct keeps track of the escrowed Asset
     */
    struct Asset {
        // expected: the agreed-upon amount to be escrowed
        uint expected;
        // current: the current amount of the asset that is escrowed in the swap.
        uint current;
        // deadline: the time before which the person escrowing their asset must do so
        uint deadline;
        // timeout: the maximum time the protocol can take, which assumes everything
        // goes to plan.
        uint timeout;
    }

    /**
    The Premium struct keeps track of the escrowed premium.
     */
    struct Premium {
        // expected: the agreed-upon amount to be escrowed as a premium
        uint expected;
        // current: the current amount of the premium that is escrowed in the swap
        uint current;
        // deadline: the time before which the person escrowing their premium must do so
        uint deadline;
    }

    /**
    Mappings that store our swap details. This contract stores multiple swaps; you can access
    information about a specific swap by using its hashLock as the key to the appropriate mapping.
     */
    mapping(bytes32 => Swap) public swaps;
    mapping(bytes32 => Asset) public assets;
    mapping(bytes32 => Premium) public premiums;

    /**
    SetUp: this event should emit when a swap is successfully setup.
     */
    event SetUp(
        address payable assetEscrower,
        address payable premiumEscrower,
        uint expectedPremium,
        uint expectedAsset,
        uint startTime,
        uint premiumDeadline,
        uint assetDeadline,
        uint assetTimeout
    );

    /**
    PremiumEscrowed: this event should emit when the premiumEscrower successfully escrows the premium
     */
    event PremiumEscrowed (
        address messageSender,
        uint amount,
        address transferFrom,
        address transferTo,
        uint currentPremium,
        uint currentAsset
    );

    /**
    AssetEscrowed: this event should emit  when the assetEscrower successfully escrows the asset
     */
    event AssetEscrowed (
        address messageSender,
        uint amount,
        address transferFrom,
        address transferTo,
        uint currentPremium,
        uint currentAsset
    );

    /**
    AssetRedeemed: this event should emit when the assetEscrower successfully escrows the asset
     */
    event AssetRedeemed(
        address messageSender,
        uint amount,
        address transferFrom,
        address transferTo,
        uint currentPremium,
        uint currentAsset
    );

    /**
    PremiumRefunded: this event should emit when the premiumEscrower successfully gets their premium refunded
     */
    event PremiumRefunded(
        address messageSender,
        uint amount,
        address transferFrom,
        address transferTo,
        uint currentPremium,
        uint currentAsset
    );

    /**
    PremiumRedeemed: this event should emit when the counterparty breaks the protocol
    and the assetEscrower redeems the  premium for breaking the protocol 
     */
    event PremiumRedeemed(
        address messageSender,
        uint amount,
        address transferFrom,
        address transferTo,
        uint currentPremium,
        uint currentAsset
    );

    /**
    AssetRefunded: this event should emit when the counterparty breaks the protocol 
    and the assetEscrower succesffully gets their asset refunded
     */
    event AssetRefunded(
        address messageSender,
        uint amount,
        address transferFrom,
        address transferTo,
        uint currentPremium,
        uint currentAsset
    );

    /**
    TODO: using modifiers for your require statements is best practice,
    but we do not require you to do so
    */ 
    modifier canSetup(bytes32 hashLock) {
        require(swaps[hashLock].assetAddress == address(0), "Should fail if address is not 0");
        _;
    }

    modifier canEscrowPremium(bytes32 hashLock) {
        require(premiums[hashLock].deadline > block.timestamp, "Abort if time is up");
        require(swaps[hashLock].premiumEscrower == msg.sender, "Sender should be the premiumEscower");
        require(premiums[hashLock].current < premiums[hashLock].expected, "Must not be already escrowed");
        require(ERC20(swaps[hashLock].assetAddress).balanceOf(msg.sender) >= premiums[hashLock].expected - premiums[hashLock].current,
        "Do not have enough balance");
        _;
    }

    modifier canEscrowAsset(bytes32 hashLock) {
        require(assets[hashLock].deadline > block.timestamp, "Abort if time is up");
        require(swaps[hashLock].assetEscrower == msg.sender, "Sender should be the assetEscower");
        require(assets[hashLock].current < assets[hashLock].expected, "Must not be already escrowed");
        require(premiums[hashLock].current >= premiums[hashLock].expected, "Premiums must be escrowed before assets");

        require(ERC20(swaps[hashLock].assetAddress).balanceOf(msg.sender) >= assets[hashLock].expected - assets[hashLock].current,
        "Do not have enough balance");
        _;
    }

    modifier canRedeemAsset(bytes32 preimage, bytes32 hashLock) {
        require(assets[hashLock].deadline > block.timestamp, "Abort if time is up");
        require(swaps[hashLock].premiumEscrower == msg.sender, "Sender should be the assetEscower");
        require(premiums[hashLock].current >= premiums[hashLock].expected, "Premiums must be escrowed before assets");
        // require(assets[hashLock].current < assets[hashLock].expected, "Must not be already escrowed");
        require(assets[hashLock].current == assets[hashLock].expected, "Assets must match expectations");

        require(sha256(abi.encode(preimage)) == hashLock, "Hash(preimage) must match the hashLock");
        _;
    }

    modifier canRefundAsset(bytes32 hashLock) 
        {
        
        require(assets[hashLock].timeout < block.timestamp, "Time is late enough");
        require(assets[hashLock].current >= assets[hashLock].expected, "Assets must match expectations");
        require(premiums[hashLock].current >= premiums[hashLock].expected, "Premiums must be escrowed");

        _;
    }

    modifier canRefundPremium(bytes32 hashLock) {
        require(assets[hashLock].timeout < block.timestamp, "Time is late enough");
        require(assets[hashLock].current < assets[hashLock].expected, "Assets may not have been escrowed");
        require(premiums[hashLock].current >= premiums[hashLock].expected, "Premiums must be escrowed");
        _;
    }

    modifier canRedeemPremium(bytes32 hashLock) {
        require(assets[hashLock].timeout < block.timestamp, "Time is late enough");
        require(premiums[hashLock].current >= premiums[hashLock].expected, "Premiums must be escrowed");
                require(assets[hashLock].current != 0, "Assets must not be 0");


        _;
    }
   
    /**
    setup is called to initialize an instance of a swap in this contract. 
    Due to storage constraints, the various parts of the swap are spread 
    out between the three different mappings above: swaps, assets, 
    and premiums.
    */
    function setup(
        uint expectedAssetEscrow,
        uint expectedPremiumEscrow,
        address payable assetEscrower,
        address payable premiumEscrower,
        address assetAddress,
        bytes32 hashLock,
        uint startTime,
        bool firstAssetEscrow,
        uint delta
    )
        public 
        payable 
        canSetup(hashLock) 
    {
        //TODO
        
        swaps[hashLock] = Swap({assetEscrower: assetEscrower, 
                                premiumEscrower: premiumEscrower, 
                                hashLock: hashLock,
                                assetAddress: assetAddress});
    

        // uint assetTimeout = 256 * delta;
        {
        uint expectedPre = expectedPremiumEscrow;
        uint expectedAss = expectedAssetEscrow;

        if (firstAssetEscrow == true) {
        assets[hashLock] = Asset({expected: expectedAss, 
                                  current: 0, 
                                  deadline: startTime + 3 * delta, 
                                  timeout: startTime + 6 * delta});

             premiums[hashLock] = Premium({expected: expectedPre,
                                        current: 0,
                                        deadline: startTime + 2 * delta}); 

            emit SetUp(assetEscrower,premiumEscrower,expectedPre,
                   expectedAss,startTime, startTime + 2 * delta,
                   startTime + 3 * delta, startTime + 6 * delta);
        } else {
            assets[hashLock] = Asset({expected: expectedAssetEscrow, 
                                  current: 0, 
                                  deadline: startTime + 4 * delta, 
                                  timeout: startTime + 5 * delta});

            premiums[hashLock] = Premium({expected: expectedPre,
                                        current: 0,
                                        deadline: startTime + 1 * delta}); 

            emit SetUp(assetEscrower,premiumEscrower,expectedPre,
                   expectedAssetEscrow,startTime, startTime + 1 * delta,
                   startTime + 4 * delta, startTime + 5 * delta);
        }
        }
       
    }

    /**
    The premium escrower has to escrow their premium for the protocol to succeed.
    */
    function escrowPremium(bytes32 hashLock)
        public
        payable
        canEscrowPremium(hashLock)
    {
       //TODO
        uint amount = premiums[hashLock].expected - premiums[hashLock].current;
        address receiver = address(this);
        // Tried this and solved the transfer receiver issue
        // console.log(amount);
        // console.log(ERC20(swaps[hashLock].assetAddress).balanceOf(msg.sender));

        ERC20(swaps[hashLock].assetAddress).transferFrom(msg.sender, receiver, amount);

        premiums[hashLock].current = premiums[hashLock].expected;

        emit PremiumEscrowed({
        messageSender: msg.sender,
        amount: amount,
        transferFrom: msg.sender,
        // Who should take this?
        transferTo: receiver,
        currentPremium: premiums[hashLock].current,
        currentAsset: assets[hashLock].current
        }
    );
    }

    /**
    The asset escrower has to escrow their premium for the protocol to succeed
    */
    function escrowAsset(bytes32 hashLock) 
        public 
        payable 
        canEscrowAsset(hashLock) 
    {
        //TODO
        uint amount = assets[hashLock].expected - assets[hashLock].current;
        address receiver = address(this);
        // Tried this and solved the transfer receiver issue
        // console.log(amount);
        // console.log(ERC20(swaps[hashLock].assetAddress).balanceOf(msg.sender));

        ERC20(swaps[hashLock].assetAddress).transferFrom(msg.sender, receiver, amount);

        assets[hashLock].current = assets[hashLock].expected;

        emit AssetEscrowed({
        messageSender: msg.sender,
        amount: amount,
        transferFrom: msg.sender,
        // Who should take this?
        transferTo: receiver,
        currentPremium: premiums[hashLock].current,
        currentAsset: assets[hashLock].current
        });
    }

    /**
    redeemAsset redeems the asset for the new owner
    */
    function redeemAsset(bytes32 preimage, bytes32 hashLock) 
        public 
        canRedeemAsset(preimage, hashLock) 
    {
        //TODO
        uint amount = assets[hashLock].expected;
        address sender = address(this);

        ERC20(swaps[hashLock].assetAddress).transfer(msg.sender, amount);

        assets[hashLock].current = 0;

        emit AssetRedeemed(msg.sender, 
        amount, sender, msg.sender, premiums[hashLock].current, 0);
        
    }

    /**
    refundPremium refunds the premiumEscrower's premium should the swap succeed
    */
    function refundPremium(bytes32 hashLock) 
        public 
        canRefundPremium(hashLock)
    {
        //TODO
        uint amount = premiums[hashLock].current;
        ERC20(swaps[hashLock].assetAddress).transfer(msg.sender, amount);

        premiums[hashLock].current = 0;

        emit PremiumRefunded({
        messageSender: msg.sender,
        amount: amount,
        transferFrom: address(this),
        // Who should take this?
        transferTo: msg.sender,
        currentPremium: premiums[hashLock].current,
        currentAsset: assets[hashLock].current
        });
    }

    /**
    refundAsset refunds the asset to its original owner should the swap fail
    */
    function refundAsset(bytes32 hashLock) 
        public 
        canRefundAsset(hashLock) 
    {
       //TODO
       uint amount = assets[hashLock].current;
        ERC20(swaps[hashLock].assetAddress).transfer(msg.sender, amount);

        assets[hashLock].current = 0;

        emit AssetRefunded({
        messageSender: msg.sender,
        amount: amount,
        transferFrom: address(this),
        // Who should take this?
        transferTo: msg.sender,
        currentPremium: premiums[hashLock].current,
        currentAsset: assets[hashLock].current
        });
    }

    /**
    redeemPremium allows a party to redeem the counterparty's premium should the swap fail
    */
    function redeemPremium(bytes32 hashLock) 
        public 
        canRedeemPremium(hashLock)
    {
        //TODO
        uint amount = premiums[hashLock].expected;
        address sender = address(this);

        ERC20(swaps[hashLock].assetAddress).transfer(msg.sender, amount);

        premiums[hashLock].current = 0;
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   
        emit PremiumRedeemed(msg.sender, 
        amount, sender, msg.sender, premiums[hashLock].current, assets[hashLock].current);
    }
}
