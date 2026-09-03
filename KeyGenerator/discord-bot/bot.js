const { Client, GatewayIntentBits, SlashCommandBuilder, REST, Routes, EmbedBuilder } = require('discord.js');
const crypto = require('crypto');

const TOKEN = 'YOUR_BOT_TOKEN_HERE';
const CLIENT_ID = 'YOUR_CLIENT_ID_HERE';
const ADMIN_ID = 'YOUR_DISCORD_USER_ID_HERE';
const SECRET = 'XRD-AGAR-SECRET-2024-ONLY-HE-KNOWS';

const client = new Client({ intents: [GatewayIntentBits.Guilds] });

function generateKey(durationHours) {
    const timestamp = Math.floor(Date.now() / 1000);
    const payload = `${timestamp}|${durationHours}`;
    const payloadB64 = Buffer.from(payload).toString('base64');
    const hmac = crypto.createHmac('sha256', SECRET).update(payloadB64).digest('hex');
    const sig = hmac.substring(0, 16);
    return `XRD-${payloadB64}-${sig}`;
}

function formatDuration(hours) {
    if (hours < 24) return `${hours} hour${hours > 1 ? 's' : ''}`;
    const days = Math.floor(hours / 24);
    if (days < 30) return `${days} day${days > 1 ? 's' : ''}`;
    const months = Math.floor(days / 30);
    return `${months} month${months > 1 ? 's' : ''}`;
}

client.on('ready', () => {
    console.log(`XRD KeyGen Bot online as ${client.user.tag}`);
});

client.on('interactionCreate', async interaction => {
    if (!interaction.isChatInputCommand()) return;

    if (interaction.user.id !== ADMIN_ID) {
        await interaction.reply({ content: 'Access denied.', ephemeral: true });
        return;
    }

    if (interaction.commandName === 'genkey') {
        const hours = interaction.options.getInteger('duration');
        const key = generateKey(hours);
        const expiry = new Date(Date.now() + hours * 3600 * 1000);

        const embed = new EmbedBuilder()
            .setTitle('XRD License Key Generated')
            .setColor(0x7551F4)
            .addFields(
                { name: 'Key', value: `\`\`\`${key}\`\`\``, inline: false },
                { name: 'Duration', value: formatDuration(hours), inline: true },
                { name: 'Expires', value: expiry.toLocaleString(), inline: true }
            )
            .setFooter({ text: 'XRD Agar.io Mod' })
            .setTimestamp();

        await interaction.reply({ embeds: [embed], ephemeral: true });
    }

    if (interaction.commandName === 'quickkey') {
        const preset = interaction.options.getString('preset');
        const presets = {
            '1h': 1, '6h': 6, '12h': 12, '1d': 24,
            '3d': 72, '1w': 168, '1m': 720, '3m': 2160, '1y': 8760
        };
        const hours = presets[preset] || 24;
        const key = generateKey(hours);
        const expiry = new Date(Date.now() + hours * 3600 * 1000);

        const embed = new EmbedBuilder()
            .setTitle('XRD Quick Key')
            .setColor(0x33CCE6)
            .setDescription(`\`\`\`${key}\`\`\``)
            .addFields(
                { name: 'Duration', value: formatDuration(hours), inline: true },
                { name: 'Expires', value: expiry.toLocaleString(), inline: true }
            )
            .setTimestamp();

        await interaction.reply({ embeds: [embed], ephemeral: true });
    }
});

async function registerCommands() {
    const rest = new REST().setToken(TOKEN);

    const commands = [
        new SlashCommandBuilder()
            .setName('genkey')
            .setDescription('Generate an XRD license key with custom duration')
            .addIntegerOption(opt =>
                opt.setName('duration')
                    .setDescription('Duration in hours')
                    .setRequired(true)
                    .setMinValue(1)
                    .setMaxValue(87600)
            ),
        new SlashCommandBuilder()
            .setName('quickkey')
            .setDescription('Generate a key with a preset duration')
            .addStringOption(opt =>
                opt.setName('preset')
                    .setDescription('Duration preset')
                    .setRequired(true)
                    .addChoices(
                        { name: '1 Hour', value: '1h' },
                        { name: '6 Hours', value: '6h' },
                        { name: '12 Hours', value: '12h' },
                        { name: '1 Day', value: '1d' },
                        { name: '3 Days', value: '3d' },
                        { name: '1 Week', value: '1w' },
                        { name: '1 Month', value: '1m' },
                        { name: '3 Months', value: '3m' },
                        { name: '1 Year', value: '1y' }
                    )
            )
    ];

    await rest.put(
        Routes.applicationCommands(CLIENT_ID),
        { body: commands.map(c => c.toJSON()) }
    );
    console.log('Slash commands registered.');
}

registerCommands();
client.login(TOKEN);
