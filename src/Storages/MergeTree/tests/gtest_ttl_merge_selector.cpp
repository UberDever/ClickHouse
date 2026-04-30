#include <memory>
#include <Storages/MergeTree/Compaction/MergeSelectors/TTLMergeSelector.h>
#include <gtest/gtest.h>

using namespace DB;

namespace
{
constexpr size_t PARTS_COUNT = 10;
constexpr time_t CURRENT_TIME = 1000;
}

struct TTLMergeSelectorSuiteParams
{
    std::function<std::unique_ptr<ITTLMergeSelector>(const PartitionIdToTTLs & merge_due_times)> construct_selector;
    size_t expected_parts_count;
};

class TTLMergeSelectorSuite : public testing::TestWithParam<TTLMergeSelectorSuiteParams>
{
};

TEST_P(TTLMergeSelectorSuite, SelectParts)
{
    const auto [construct_selector, expected_parts_count] = GetParam();
    PartsRange parts_range;

    for (int i = 0; i < PARTS_COUNT; ++i)
    {
        parts_range.push_back(
            PartProperties{
                .name = "all_" + std::to_string(i) + "_" + std::to_string(i) + "_0",
                .info = MergeTreePartInfo::fromPartName(
                    "all_" + std::to_string(i) + "_" + std::to_string(i) + "_0",
                    MERGE_TREE_DATA_MIN_FORMAT_VERSION_WITH_CUSTOM_PARTITIONING),
                .size = 10 * 1024,
                .age = 0,
                .rows = 100,
                .general_ttl_info = PartProperties::GeneralTTLInfo{
                    .has_any_non_finished_ttls = true,
                    .part_min_ttl = CURRENT_TIME - 100,
                    .part_max_ttl = CURRENT_TIME - 50,
                }});
    }

    PartitionIdToTTLs merge_due_times;
    auto selector = construct_selector(merge_due_times);

    std::array<MergeConstraint, 1> constraints{MergeConstraint{std::numeric_limits<size_t>::max(), std::numeric_limits<size_t>::max()}};

    auto selected = selector->select({parts_range}, constraints, nullptr);

    ASSERT_FALSE(selected.empty());
    ASSERT_LE(selected[0].size(), expected_parts_count);
}

INSTANTIATE_TEST_SUITE_P(
    TTLTests,
    TTLMergeSelectorSuite,
    testing::Values(
        TTLMergeSelectorSuiteParams{
            .construct_selector = [](const PartitionIdToTTLs & merge_due_times) -> std::unique_ptr<ITTLMergeSelector>
            { return std::make_unique<TTLRowDeleteMergeSelector>(merge_due_times, CURRENT_TIME, 3); },
            .expected_parts_count = 3},
        TTLMergeSelectorSuiteParams{
            .construct_selector = [](const PartitionIdToTTLs & merge_due_times) -> std::unique_ptr<ITTLMergeSelector>
            { return std::make_unique<TTLRowDeleteMergeSelector>(merge_due_times, CURRENT_TIME); },
            .expected_parts_count = PARTS_COUNT},
        TTLMergeSelectorSuiteParams{
            .construct_selector = []([[maybe_unused]] const PartitionIdToTTLs & merge_due_times) -> std::unique_ptr<ITTLMergeSelector>
            { return std::make_unique<TTLPartDropMergeSelector>(CURRENT_TIME, 3); },
            .expected_parts_count = 3}));
