#!/usr/bin/env node

declare const process: {
  argv: string[];
  exit(code?: number): never;
};
declare function require(name: string): {
  readFileSync(path: string, encoding: string): string;
  writeFileSync(path: string, data: string, encoding: string): void;
};
const { readFileSync, writeFileSync } = require('fs');

const MINED_RESOURCE_BASE_COST = 10;
const PRODUCTION_FACTOR = 1.1;
const DEFAULT_DATA_RAW_URL = 'https://gist.githubusercontent.com/Bilka2/6b8a6a9e4a4ec779573ad703d03c1ae7/raw';
const REQUIRED_ITEMS = ['inserter', 'wooden-chest', 'steel-chest', 'solar-panel', 'satellite', 'crude-oil'];
const FULL_DUMP_MIN_RECIPES = 200;
const FULL_DUMP_REQUIRED_PROTOTYPES = ['item', 'fluid', 'recipe', 'resource', 'technology'];
const FULL_DUMP_REQUIRED_RECIPES = ['inserter', 'solar-panel', 'satellite', 'assembling-machine-1'];

type LuaArrayEntry = [string, number] | [string];
type RawEntry = Record<string, unknown> | LuaArrayEntry;
type RawMap = Record<string, Record<string, unknown>>;
type DataRaw = {
  resource?: RawMap;
  recipe?: RawMap;
};

type PriceMap = Record<string, number>;
type NameAmount = [string, number];

type CliOptions = {
  input?: string;
  inputUrl: string;
  output: string;
};

function parseArgs(argv: string[]): CliOptions {
  const options: CliOptions = {
    inputUrl: DEFAULT_DATA_RAW_URL,
    output: 'src/suggested-prices-config.lua',
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--input' && argv[i + 1]) {
      options.input = argv[++i];
    } else if (arg === '--input-url' && argv[i + 1]) {
      options.inputUrl = argv[++i];
    } else if (arg === '--output' && argv[i + 1]) {
      options.output = argv[++i];
    } else if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    }
  }

  return options;
}

function printHelp(): void {
  console.log(`Usage: node src/generate_suggested_prices_config.js [options]

Options:
  --input <path>      Path to Factorio script-output/data-raw-dump.json
  --input-url <url>   Fallback URL for full data.raw serialization
  --output <path>     Output Lua config path (default: src/suggested-prices-config.lua)
  -h, --help          Show this help message`);
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

function calculatePrices(raw: DataRaw): PriceMap {
  const prices: PriceMap = {};

  for (const resourceName of extractMinedResources(raw)) {
    prices[resourceName] = MINED_RESOURCE_BASE_COST;
  }
  addPumpSeedCosts(raw, prices);

  const recipes = raw.recipe ?? {};

  let changed = true;
  for (let pass = 0; pass < 10000 && changed; pass += 1) {
    changed = false;

    for (const recipe of Object.values(recipes)) {
      if (recipe.hidden === true) {
        continue;
      }

      for (const variant of recipeVariants(recipe)) {
        const ingredients = extractIngredients(variant);
        const products = extractProducts(variant);
        if (ingredients.length === 0 || products.length === 0) {
          continue;
        }

        if (!ingredients.every(([name]) => prices[name] !== undefined)) {
          continue;
        }

        const totalInputCost = ingredients.reduce((total, [name, amount]) => total + prices[name] * amount, 0);

        for (const [productName, productAmount] of products) {
          if (productAmount <= 0) {
            continue;
          }

          const candidate = (totalInputCost * PRODUCTION_FACTOR) / productAmount;
          if (prices[productName] === undefined || candidate < prices[productName]) {
            prices[productName] = candidate;
            changed = true;
          }
        }
      }
    }
  }

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

function writeLuaConfig(prices: PriceMap, outputPath: string): void {
  const lines: string[] = [
    '-- suggested-prices-config.lua',
    '-- Auto-generated by src/generate_suggested_prices_config.ts',
    `-- mined resource base cost = ${MINED_RESOURCE_BASE_COST}`,
    `-- production factor = ${PRODUCTION_FACTOR}`,
    'return {',
  ];

  for (const name of Object.keys(prices).sort()) {
    lines.push(`  ["${name}"] = ${Math.round(prices[name])},`);
  }

  lines.push('}');
  writeFileSync(outputPath, `${lines.join('\n')}\n`, 'utf8');
}

async function loadDataRaw(options: CliOptions): Promise<DataRaw> {
  if (options.input) {
    return JSON.parse(readFileSync(options.input, 'utf8')) as DataRaw;
  }

  const response = await fetch(options.inputUrl);
  if (!response.ok) {
    throw new Error(`Failed to download ${options.inputUrl}: HTTP ${response.status}`);
  }
  return (await response.json()) as DataRaw;
}

async function main(): Promise<void> {
  const options = parseArgs(process.argv.slice(2));
  const raw = await loadDataRaw(options);
  validateFullDump(raw);
  const prices = calculatePrices(raw);
  const missingRequiredItems = REQUIRED_ITEMS.filter((name) => prices[name] === undefined);
  if (missingRequiredItems.length > 0) {
    throw new Error(
      `Generated data is missing required items: ${missingRequiredItems.join(', ')}. ` +
        'Input source is likely incomplete.',
    );
  }
  writeLuaConfig(prices, options.output);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
