using BiliRemote.Core;
using Xunit;

namespace BiliRemote.Tests;

public class QualityTests
{
    [Fact]
    public void BrowserQualityStateSurvivesHostSerialization()
    {
        var source = Wire.Element(new { bvid = "BVtest", quality = new { currentId = "80", currentLabel = "1080P 高清", width = 1920, height = 1080, options = new[] { new { id = "112", label = "1080P 高码率", badge = "大会员", disabled = false } } } });
        var state = Wire.Decode<PlayerState>(source);
        var snapshot = Wire.Element(state).GetProperty("quality");
        Assert.Equal("80", snapshot.Text("currentId"));
        Assert.Equal(1920, snapshot.Number("width"));
        Assert.Equal("大会员", snapshot.GetProperty("options")[0].Text("badge"));
        Assert.False(snapshot.GetProperty("options")[0].Flag("disabled"));
    }
    [Fact]
    public void OlderExtensionStatesRemainReadable()
    {
        var state = Wire.Decode<PlayerState>(Wire.Element(new { bvid = "BVtest" }));
        Assert.Null(state.Quality);
        Assert.False(Wire.Element(state).TryGetProperty("quality", out _));
    }
}
