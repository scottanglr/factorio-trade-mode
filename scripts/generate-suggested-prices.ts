#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { parse as parseLua } from 'luaparse';

const MINED_RESOURCE_BASE_COST = 10;
const PRODUCTION_FACTOR = 1.1;
const FACTORIO_IMPLICIT_RECIPE_CRAFTING_TIME_SECONDS = 0.5;
const JOULES_PER_PRICE_ENERGY_UNIT = 400_000;
const COAL_FALLBACK_ENERGY_UNITS = 10;
const ENERGY_UNITS_PER_CRAFTING_SECOND = 1;
const DEFAULT_DATA_RAW_URL = 'https://gist.githubusercontent.com/Bilka2/6b8a6a9e4a4ec779573ad703d03c1ae7/raw';
const REQUIRED_ITEMS = ['inserter', 'steel-chest', 'solar-panel', 'rocket-part', 'crude-oil'];
const FULL_DUMP_MIN_RECIPES = 200;
const FULL_DUMP_REQUIRED_PROTOTYPES = ['item', 'fluid', 'recipe', 'resource', 'technology'];
const FULL_DUMP_REQUIRED_RECIPES = ['inserter', 'solar-panel', 'rocket-part', 'assembling-machine-1'];

type LuaArrayEntry = [string, number] | [string];
type RawEntry = Record<string, unknown> | LuaArrayEntry;
type RawMap = Record<string, Record<string, unknown>>;
type DataRaw = {
  resource?: RawMap;
  recipe?: RawMap;
  item?: RawMap;
};

type PriceMap = Record<string, number>;
type NameAmount = [string, number];
type CraftingTimeSummary = {
  implicitDefaultCount: number;
  explicitDefaultCount: number;
  explicitNonDefaultCount: number;
  explicitNonDefaultExamples: Array<{ name: string; seconds: number }>;
};

type CliOptions = {
  input?: string;
  inputUrl: string;
  outputVanilla: string;
  outputSpaceAge: string;
  verbose: boolean;
  traceCandidates: boolean;
};

type PriceMode = 'vanilla' | 'space_age';

function parseArgs(argv: string[]): CliOptions {
  const options: CliOptions = {
    inputUrl: DEFAULT_DATA_RAW_URL,
    outputVanilla: 'trade_mode/suggested-prices-vanilla.lua',
    outputSpaceAge: 'trade_mode/suggested-prices-space-age.lua',
    verbose: false,
    traceCandidates: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--input' && argv[i + 1]) {
      options.input = argv[++i];
    } else if (arg === '--input-url' && argv[i + 1]) {
      options.inputUrl = argv[++i];
    } else if (arg === '--output' && argv[i + 1]) {
      options.outputSpaceAge = argv[++i];
    } else if (arg === '--output-space-age' && argv[i + 1]) {
      options.outputSpaceAge = argv[++i];
    } else if (arg === '--output-vanilla' && argv[i + 1]) {
      options.outputVanilla = argv[++i];
    } else if (arg === '--verbose' || arg === '-v') {
      options.verbose = true;
    } else if (arg === '--trace-candidates') {
      options.traceCandidates = true;
    } else if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    }
  }

  return options;
}

function printHelp(): void {
  console.log(`Usage: node scripts/generate-suggested-prices.js [options]

Options:
  --input <path>      Path to Factorio script-output/data-raw-dump.json
  --input-url <url>   URL to full data.raw dump (JSON or Lua/Serpent)
  --output <path>     Output Lua config path for Space Age (default: trade_mode/suggested-prices-space-age.lua)
  --output-space-age <path>  Output Lua config path for Space Age prices
  --output-vanilla <path>    Output Lua config path for vanilla prices
  -v, --verbose       Print detailed progress logs
  --trace-candidates  Include per-recipe candidate pricing logs (very verbose)
  -h, --help          Show this help message`);
}

type Logger = {
  info: (message: string) => void;
  candidate: (message: string) => void;
};

function createLogger(options: CliOptions): Logger {
  return {
    info: (message: string) => {
      if (options.verbose || options.traceCandidates) {
        console.log(`[pricing] ${message}`);
      }
    },
    candidate: (message: string) => {
      if (options.traceCandidates) {
        console.log(`[pricing:candidate] ${message}`);
      }
    },
  };
}

type LuaAstNode = {
  type: string;
  [key: string]: unknown;
};

function parseLuaChunk(source: string): LuaAstNode | undefined {
  try {
    return parseLua(source, {
      comments: false,
      scope: false,
      locations: false,
      ranges: false,
    }) as unknown as LuaAstNode;
  } catch {
    return undefined;
  }
}

function findSingleReturnedLuaValue(statements: LuaAstNode[]): LuaAstNode | undefined {
  for (const statement of statements) {
    if (statement.type === 'ReturnStatement') {
      const args = statement.arguments as LuaAstNode[];
      if (!args || args.length !== 1) {
        throw new Error('Lua dump must return exactly one top-level value.');
      }
      return args[0];
    }

    if (statement.type === 'DoStatement') {
      const body = statement.body;
      if (Array.isArray(body)) {
        const value = findSingleReturnedLuaValue(body as LuaAstNode[]);
        if (value) {
          return value;
        }
      }
    }
  }

  return undefined;
}

function decodeLuaStringLiteral(raw: string): string {
  const quote = raw[0];
  const body = raw.slice(1, -1);
  let out = '';
  for (let i = 0; i < body.length; i += 1) {
    const ch = body[i];
    if (ch !== '\\') {
      out += ch;
      continue;
    }

    i += 1;
    if (i >= body.length) {
      break;
    }
    const esc = body[i];
    switch (esc) {
      case 'a':
        out += '\u0007';
        break;
      case 'b':
        out += '\b';
        break;
      case 'f':
        out += '\f';
        break;
      case 'n':
        out += '\n';
        break;
      case 'r':
        out += '\r';
        break;
      case 't':
        out += '\t';
        break;
      case 'v':
        out += '\u000b';
        break;
      case '\\':
      case '"':
      case "'":
        out += esc;
        break;
      case 'z':
        while (i + 1 < body.length && /\s/.test(body[i + 1])) {
          i += 1;
        }
        break;
      case 'x': {
        const hex = body.slice(i + 1, i + 3);
        if (/^[0-9a-fA-F]{2}$/.test(hex)) {
          out += String.fromCharCode(parseInt(hex, 16));
          i += 2;
        } else {
          out += 'x';
        }
        break;
      }
      default:
        if (/[0-9]/.test(esc)) {
          let digits = esc;
          while (i + 1 < body.length && digits.length < 3 && /[0-9]/.test(body[i + 1])) {
            i += 1;
            digits += body[i];
          }
          out += String.fromCharCode(parseInt(digits, 10));
          break;
        }
        out += esc;
    }
  }
  if (quote !== '"' && quote !== "'") {
    throw new Error(`Unsupported Lua string delimiter: ${quote}`);
  }
  return out;
}

function parseLuaDumpPayload(payload: string): unknown {
  const trimmed = payload.trimStart();
  const body = trimmed.startsWith('Script @__DataRawSerpent__/')
    ? trimmed.replace(/^Script @__DataRawSerpent__\/.*?:\s*/, '')
    : trimmed;
  const ast = parseLuaChunk(body) ?? parseLuaChunk(`return ${body}`);
  if (!ast) {
    throw new Error('Lua dump could not be parsed as a Lua chunk or table expression.');
  }
  const chunkBody = ast.body as LuaAstNode[];
  const returnedValue = findSingleReturnedLuaValue(chunkBody);
  if (!returnedValue) {
    throw new Error('Lua dump did not contain a return value.');
  }
  return luaNodeToJs(returnedValue);
}

function luaNodeToJs(node: LuaAstNode): unknown {
  switch (node.type) {
    case 'TableConstructorExpression': {
      const fields = node.fields as LuaAstNode[];
      const keyed: Record<string, unknown> = {};
      const arrayValues: unknown[] = [];
      for (const field of fields) {
        if (field.type === 'TableValue') {
          arrayValues.push(luaNodeToJs(field.value as LuaAstNode));
          continue;
        }
        if (field.type === 'TableKeyString') {
          const key = ((field.key as LuaAstNode).name as string) ?? '';
          keyed[key] = luaNodeToJs(field.value as LuaAstNode);
          continue;
        }
        if (field.type === 'TableKey') {
          const key = luaNodeToJs(field.key as LuaAstNode);
          keyed[String(key)] = luaNodeToJs(field.value as LuaAstNode);
          continue;
        }
        throw new Error(`Unsupported Lua table field type: ${field.type}`);
      }
      if (Object.keys(keyed).length === 0) {
        return arrayValues;
      }
      for (let i = 0; i < arrayValues.length; i += 1) {
        keyed[String(i + 1)] = arrayValues[i];
      }
      return keyed;
    }
    case 'StringLiteral': {
      if (typeof node.value === 'string') {
        return node.value;
      }
      const raw = node.raw;
      if (typeof raw !== 'string' || raw.length < 2) {
        throw new Error('Unsupported Lua string literal.');
      }
      return decodeLuaStringLiteral(raw);
    }
    case 'NumericLiteral':
      return typeof node.value === 'number' ? node.value : Number(node.raw);
    case 'BooleanLiteral':
      return typeof node.value === 'boolean' ? node.value : node.raw === 'true';
    case 'NilLiteral':
      return null;
    case 'UnaryExpression':
      if (node.operator === '-' && (node.argument as LuaAstNode).type === 'NumericLiteral') {
        return -((node.argument as LuaAstNode).value as number);
      }
      throw new Error(`Unsupported unary expression in Lua dump: ${String(node.operator)}`);
    default:
      throw new Error(`Unsupported Lua AST node type: ${node.type}`);
  }
}

function parseDataRaw(payload: string): DataRaw {
  try {
    return JSON.parse(payload) as DataRaw;
  } catch {
    return parseLuaDumpPayload(payload) as DataRaw;
  }
}

function entryName(entry: RawEntry): string | undefined {
  if (Array.isArray(entry)) {
    return typeof entry[0] === 'string' ? entry[0] : undefined;
  }
  return typeof entry.name === 'string' ? entry.name : undefined;
}

function entryAmount(entry: RawEntry): number {
  if (Array.isArray(entry)) {
    const amount = entry[1];
    return typeof amount === 'number' ? amount : 1;
  }

  if (typeof entry.amount === 'number') {
    return entry.amount;
  }

  if (typeof entry.amount_min === 'number' && typeof entry.amount_max === 'number') {
    return (entry.amount_min + entry.amount_max) / 2;
  }

  if (typeof entry.probability === 'number') {
    return entry.probability;
  }

  return 1;
}

function extractIngredients(recipe: Record<string, unknown>): NameAmount[] {
  const ingredients = recipe.ingredients;
  if (!Array.isArray(ingredients)) {
    return [];
  }

  const out: NameAmount[] = [];
  for (const ingredient of ingredients as RawEntry[]) {
    const name = entryName(ingredient);
    if (!name) {
      continue;
    }
    out.push([name, entryAmount(ingredient)]);
  }
  return out;
}

function extractProducts(recipe: Record<string, unknown>): NameAmount[] {
  if (Array.isArray(recipe.results)) {
    const out: NameAmount[] = [];
    for (const product of recipe.results as RawEntry[]) {
      const name = entryName(product);
      if (!name) {
        continue;
      }

      let amount = entryAmount(product);
      if (!Array.isArray(product) && typeof product.probability === 'number') {
        amount *= product.probability;
      }
      out.push([name, amount]);
    }
    return out;
  }

  if (typeof recipe.result === 'string') {
    const resultCount = typeof recipe.result_count === 'number' ? recipe.result_count : 1;
    return [[recipe.result, resultCount]];
  }

  return [];
}

function extractMinedResources(raw: DataRaw): Set<string> {
  const mined = new Set<string>();
  const resources = raw.resource ?? {};

  for (const resource of Object.values(resources)) {
    const minable = resource.minable;
    if (typeof minable !== 'object' || minable === null) {
      continue;
    }

    const minableObj = minable as Record<string, unknown>;
    if (Array.isArray(minableObj.results)) {
      for (const result of minableObj.results as RawEntry[]) {
        const name = entryName(result);
        if (name) {
          mined.add(name);
        }
      }
    } else if (typeof minableObj.result === 'string') {
      mined.add(minableObj.result);
    }
  }

  return mined;
}

function recipeVariants(recipe: Record<string, unknown>): Record<string, unknown>[] {
  const variants: Record<string, unknown>[] = [recipe];

  if (recipe.normal && typeof recipe.normal === 'object') {
    variants.push({ ...recipe, ...(recipe.normal as Record<string, unknown>) });
  }
  if (recipe.expensive && typeof recipe.expensive === 'object') {
    variants.push({ ...recipe, ...(recipe.expensive as Record<string, unknown>) });
  }

  return variants;
}

function addPumpSeedCosts(raw: DataRaw, prices: PriceMap): void {
  const offshorePump = (raw as Record<string, RawMap>)['offshore-pump'] ?? {};
  for (const pump of Object.values(offshorePump)) {
    const fluid = pump.fluid;
    if (typeof fluid === 'string' && prices[fluid] === undefined) {
      prices[fluid] = MINED_RESOURCE_BASE_COST;
    }
  }
}

function parseEnergyToJoules(energy: unknown): number | undefined {
  if (typeof energy !== 'string') {
    return undefined;
  }

  const trimmed = energy.trim();
  const match = /^([0-9]+(?:\.[0-9]+)?)\s*([kMGTPEZYRQ]?)([JW])$/.exec(trimmed);
  if (!match) {
    return undefined;
  }

  const magnitude = Number(match[1]);
  if (!Number.isFinite(magnitude) || magnitude <= 0) {
    return undefined;
  }

  const multiplierMap: Record<string, number> = {
    '': 1,
    k: 1e3,
    M: 1e6,
    G: 1e9,
    T: 1e12,
    P: 1e15,
    E: 1e18,
    Z: 1e21,
    Y: 1e24,
    R: 1e27,
    Q: 1e30,
  };
  const multiplier = multiplierMap[match[2]];
  if (multiplier === undefined) {
    return undefined;
  }

  const unit = match[3];
  const value = magnitude * multiplier;
  if (unit === 'J') {
    return value;
  }

  // Watt is Joule/second. For fuel_value we expect joules, but keep a deterministic fallback.
  return value;
}

function coalEnergyUnits(raw: DataRaw): number {
  const coal = raw.item?.coal;
  const fuelValueJoules = coal ? parseEnergyToJoules((coal as Record<string, unknown>).fuel_value) : undefined;
  if (!fuelValueJoules || fuelValueJoules <= 0) {
    return COAL_FALLBACK_ENERGY_UNITS;
  }

  const units = fuelValueJoules / JOULES_PER_PRICE_ENERGY_UNIT;
  if (!Number.isFinite(units) || units <= 0) {
    return COAL_FALLBACK_ENERGY_UNITS;
  }
  return units;
}

function extractRecipeCraftingTimeSeconds(recipe: Record<string, unknown>): number {
  // Factorio recipe prototypes store crafting time in `energy_required`.
  // When omitted in data.raw, Factorio's actual implicit recipe time is 0.5 seconds.
  return typeof recipe.energy_required === 'number' ? recipe.energy_required : FACTORIO_IMPLICIT_RECIPE_CRAFTING_TIME_SECONDS;
}

function summarizeCraftingTimes(raw: DataRaw): CraftingTimeSummary {
  const summary: CraftingTimeSummary = {
    implicitDefaultCount: 0,
    explicitDefaultCount: 0,
    explicitNonDefaultCount: 0,
    explicitNonDefaultExamples: [],
  };
  const recipes = raw.recipe ?? {};
  for (const recipe of Object.values(recipes)) {
    if (recipe.hidden === true) {
      continue;
    }
    for (const variant of recipeVariants(recipe)) {
      const name = typeof variant.name === 'string' ? variant.name : '(unknown)';
      const energyRequired = variant.energy_required;
      if (typeof energyRequired !== 'number') {
        summary.implicitDefaultCount += 1;
        continue;
      }
      if (energyRequired === FACTORIO_IMPLICIT_RECIPE_CRAFTING_TIME_SECONDS) {
        summary.explicitDefaultCount += 1;
        continue;
      }
      summary.explicitNonDefaultCount += 1;
      if (summary.explicitNonDefaultExamples.length < 10) {
        summary.explicitNonDefaultExamples.push({ name, seconds: energyRequired });
      }
    }
  }
  return summary;
}

function isSpaceOnlyRecipeVariant(variant: Record<string, unknown>): boolean {
  const surfaceConditions = variant.surface_conditions;
  return Array.isArray(surfaceConditions) && surfaceConditions.length > 0;
}

function calculatePrices(raw: DataRaw, logger: Logger, mode: PriceMode): PriceMap {
  const prices: PriceMap = {};

  const minedResources = extractMinedResources(raw);
  logger.info(`[${mode}] Seeding ${minedResources.size} mined resources at base cost ${MINED_RESOURCE_BASE_COST}.`);
  for (const resourceName of minedResources) {
    prices[resourceName] = MINED_RESOURCE_BASE_COST;
  }
  addPumpSeedCosts(raw, prices);
  const energyUnitPrice = (prices.coal ?? MINED_RESOURCE_BASE_COST) / coalEnergyUnits(raw);
  logger.info(`[${mode}] Energy unit price derived from coal: ${energyUnitPrice.toFixed(4)}.`);

  const recipes = raw.recipe ?? {};
  logger.info(`[${mode}] Loaded ${Object.keys(recipes).length} total recipes.`);
  const productsWithDirectBaseRecipe = new Set<string>();
  for (const recipe of Object.values(recipes)) {
    for (const variant of recipeVariants(recipe)) {
      if (mode === 'vanilla' && isSpaceOnlyRecipeVariant(variant)) {
        continue;
      }
      if (typeof variant.name !== 'string') {
        continue;
      }
      for (const [productName] of extractProducts(variant)) {
        if (productName === variant.name) {
          productsWithDirectBaseRecipe.add(productName);
        }
      }
    }
  }
  logger.info(`[${mode}] Identified ${productsWithDirectBaseRecipe.size} products with direct base recipes.`);

  let changed = true;
  for (let pass = 0; pass < 10000 && changed; pass += 1) {
    changed = false;
    let updatesThisPass = 0;
    let consideredThisPass = 0;
    let skippedHidden = 0;
    let skippedNoIngredientsOrProducts = 0;
    let skippedMissingInputs = 0;
    let skippedBlockedByDirectBase = 0;
    logger.info(`[${mode}] Starting pass ${pass + 1}.`);

    for (const recipe of Object.values(recipes)) {
      if (recipe.hidden === true) {
        skippedHidden += 1;
        continue;
      }

      for (const variant of recipeVariants(recipe)) {
        if (mode === 'vanilla' && isSpaceOnlyRecipeVariant(variant)) {
          continue;
        }
        consideredThisPass += 1;
        const ingredients = extractIngredients(variant);
        const products = extractProducts(variant);
        if (ingredients.length === 0 || products.length === 0) {
          skippedNoIngredientsOrProducts += 1;
          continue;
        }

        if (!ingredients.every(([name]) => prices[name] !== undefined)) {
          skippedMissingInputs += 1;
          continue;
        }

        const totalInputCost = ingredients.reduce((total, [name, amount]) => total + prices[name] * amount, 0);
        const recipeCraftingTimeSeconds = extractRecipeCraftingTimeSeconds(variant);
        const recipeEnergyCost =
          recipeCraftingTimeSeconds * ENERGY_UNITS_PER_CRAFTING_SECOND * energyUnitPrice;
        const totalCostWithEnergy = totalInputCost * PRODUCTION_FACTOR + recipeEnergyCost;
        const recipeName = typeof variant.name === 'string' ? variant.name : '';

        for (const [productName, productAmount] of products) {
          if (productAmount <= 0) {
            continue;
          }
          if (productsWithDirectBaseRecipe.has(productName) && recipeName !== productName) {
            skippedBlockedByDirectBase += 1;
            continue;
          }

          const candidate = totalCostWithEnergy / productAmount;
          logger.candidate(
            `${recipeName || '<unnamed>'} -> ${productName} amount=${productAmount} ` +
              `inputs=${totalInputCost.toFixed(2)} energy=${recipeEnergyCost.toFixed(2)} ` +
              `candidate=${candidate.toFixed(4)}`,
          );
          if (prices[productName] === undefined || candidate < prices[productName]) {
            const previous = prices[productName];
            prices[productName] = candidate;
            changed = true;
            updatesThisPass += 1;
            logger.info(
              `[${mode}] Price update for ${productName}: ${previous === undefined ? 'unset' : previous.toFixed(4)} -> ${candidate.toFixed(4)} via ${recipeName || '<unnamed>'}.`,
            );
          }
        }
      }
    }

    logger.info(
      `[${mode}] Completed pass ${pass + 1}: considered=${consideredThisPass}, updates=${updatesThisPass}, ` +
        `skipped(hidden=${skippedHidden}, empty=${skippedNoIngredientsOrProducts}, missing-inputs=${skippedMissingInputs}, direct-base-guard=${skippedBlockedByDirectBase}), changed=${changed}.`,
    );
  }

  if (mode === 'vanilla' && prices['space-science-pack'] === undefined && prices['rocket-part'] !== undefined) {
    prices['space-science-pack'] = prices['rocket-part'] / 10;
    logger.info(
      `[${mode}] Added fallback vanilla space-science-pack price from rocket-part/10 = ${prices['space-science-pack'].toFixed(4)}.`,
    );
  }

  logger.info(`[${mode}] Finished pricing with ${Object.keys(prices).length} priced entries.`);
  return prices;
}

function validateFullDump(raw: DataRaw): void {
  const root = raw as Record<string, unknown>;
  const missingPrototypeGroups = FULL_DUMP_REQUIRED_PROTOTYPES.filter((key) => {
    const value = root[key];
    return typeof value !== 'object' || value === null;
  });

  if (missingPrototypeGroups.length > 0) {
    throw new Error(
      `Input is not a full Factorio data dump. Missing prototype groups: ${missingPrototypeGroups.join(', ')}.`,
    );
  }

  const recipes = raw.recipe ?? {};
  if (Object.keys(recipes).length < FULL_DUMP_MIN_RECIPES) {
    throw new Error(
      `Input appears partial: only ${Object.keys(recipes).length} recipes found. ` +
        'A full vanilla dump should contain substantially more.',
    );
  }

  const missingKnownRecipes = FULL_DUMP_REQUIRED_RECIPES.filter((name) => recipes[name] === undefined);
  if (missingKnownRecipes.length > 0) {
    throw new Error(
      `Input appears partial: missing expected vanilla recipes ${missingKnownRecipes.join(', ')}.`,
    );
  }
}

function writeLuaConfig(prices: PriceMap, outputPath: string, label: string): void {
  const lines: string[] = [
    `-- ${label}`,
    '-- Auto-generated by scripts/generate-suggested-prices.ts',
    `-- mined resource base cost = ${MINED_RESOURCE_BASE_COST}`,
    `-- production factor = ${PRODUCTION_FACTOR}`,
    `-- joules per price-energy unit = ${JOULES_PER_PRICE_ENERGY_UNIT}`,
    `-- fallback coal energy units = ${COAL_FALLBACK_ENERGY_UNITS}`,
    `-- crafting-second energy units = ${ENERGY_UNITS_PER_CRAFTING_SECOND}`,
    '-- recipe energy cost = recipe_seconds * (coal_price / coal_energy_units)',
    'return {',
  ];

  for (const name of Object.keys(prices).sort()) {
    lines.push(`  ["${name}"] = ${Math.round(prices[name])},`);
  }

  lines.push('}');
  writeFileSync(outputPath, `${lines.join('\n')}\n`, 'utf8');
}

async function downloadDataRaw(url: string): Promise<string> {
  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    return await response.text();
  } catch (fetchError) {
    try {
      return execFileSync(
        'curl',
        ['-L', '--fail', '--silent', '--show-error', url],
        { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 },
      );
    } catch (curlError) {
      throw new Error(
        `Failed to download ${url}. fetch error: ${String(fetchError)}. curl error: ${String(curlError)}`,
      );
    }
  }
}

async function loadDataRaw(options: CliOptions): Promise<DataRaw> {
  if (options.input) {
    return parseDataRaw(readFileSync(options.input, 'utf8'));
  }

  return parseDataRaw(await downloadDataRaw(options.inputUrl));
}

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  const logger = createLogger(options);
  logger.info(
    `Starting suggested price generation. outputs: vanilla=${options.outputVanilla}, space_age=${options.outputSpaceAge}`,
  );
  logger.info(
    options.input
      ? `Loading data.raw payload from file: ${options.input}`
      : `Loading data.raw payload from URL: ${options.inputUrl}`,
  );
  const raw = await loadDataRaw(options);
  logger.info('Parsed data.raw payload successfully.');
  validateFullDump(raw);
  logger.info('Validated full dump input.');
  const craftingTimeSummary = summarizeCraftingTimes(raw);
  console.log(
    `[craft-time] implicit-default=${craftingTimeSummary.implicitDefaultCount} ` +
      `explicit-default=${craftingTimeSummary.explicitDefaultCount} ` +
      `explicit-non-default=${craftingTimeSummary.explicitNonDefaultCount}`,
  );
  if (craftingTimeSummary.explicitNonDefaultExamples.length > 0) {
    console.log(
      `[craft-time] explicit-non-default examples: ${craftingTimeSummary.explicitNonDefaultExamples
        .map((entry) => `${entry.name}=${entry.seconds}s`)
        .join(', ')}`,
    );
  }
  const vanillaPrices = calculatePrices(raw, logger, 'vanilla');
  const spaceAgePrices = calculatePrices(raw, logger, 'space_age');
  const missingRequiredItems = REQUIRED_ITEMS.filter(
    (name) => vanillaPrices[name] === undefined || spaceAgePrices[name] === undefined,
  );
  if (missingRequiredItems.length > 0) {
    throw new Error(
      `Generated data is missing required items: ${missingRequiredItems.join(', ')}. ` +
        'Input source is likely incomplete.',
    );
  }
  writeLuaConfig(vanillaPrices, options.outputVanilla, 'suggested-prices-vanilla.lua');
  writeLuaConfig(spaceAgePrices, options.outputSpaceAge, 'suggested-prices-space-age.lua');
  logger.info(`Wrote vanilla suggested prices to ${options.outputVanilla}.`);
  logger.info(`Wrote space age suggested prices to ${options.outputSpaceAge}.`);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
